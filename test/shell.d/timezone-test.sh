#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

timezone_menu="$ROOT/bin/omarchy-menu-timezone"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-tzupdate"

grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/timedatectl ^set-timezone [A-Za-z0-9_+][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+][A-Za-z0-9_+.-]*)*$' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule allows passwordless timedatectl timezone changes"

! grep -F 'set-timezone *' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule uses a bare wildcard that admits extra arguments like -H and -M"

! grep -F 'tzupdate' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule does not grant passwordless tzupdate"

grep -F 'sudo timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu uses the passwordless sudoers timedatectl rule"

! grep -F 'pkexec timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not wrap timedatectl in pkexec"

! grep -F 'pkexec /usr/bin/timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not wrap timedatectl in pkexec"

! grep -F 'sudo /usr/bin/timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu lets sudo resolve timedatectl from its secure path"

! grep -Fx 'timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not use bare timedatectl, which triggers polkit"

grep -F 'omarchy-shell -q omarchy.clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu refreshes the namespaced clock IPC target"

! grep -F 'omarchy-shell -q Clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu no longer refreshes the retired Clock IPC target"

pass "timezone menu refreshes clock after timezone changes"

first_run_tz="$ROOT/install/user/first-run/timezone.sh"
grep -F 'first-run/timezone.sh' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first-run prompts for the timezone"
grep -F -- '--exec omarchy-launch-floating-terminal-with-presentation omarchy-menu-timezone' \
  "$first_run_tz" >/dev/null ||
  fail "first-run timezone toast passes --exec as separate words"
! grep -F -- '--exec "' "$first_run_tz" >/dev/null ||
  fail "first-run timezone toast does not quote --exec as one string"
! grep -F 'omarchy-cmd-tzupdate-enhanced' "$first_run_tz" >/dev/null ||
  fail "first-run timezone toast uses the timezone menu, not a Mac-only helper"
pass "first-run timezone toast matches notification-send --exec argv"

require_command jq
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home"
cat >"$test_tmp/bin/timedatectl" <<'STUB'
#!/bin/bash
printf '%s\n' "$OMARCHY_TEST_TIMEZONE"
STUB
cat >"$test_tmp/bin/busctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFICATION_ARGS"
STUB
chmod +x "$test_tmp/bin/"*
notification_args="$test_tmp/notification-args"
# $2 names the image root: an image-built one keeps its manifest, retired
# (target.booted) or not; an ISO install has none.
run_timezone() {
  rm -f "$notification_args"
  HOME="$test_tmp/home" PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    OMARCHY_PATH="$ROOT" OMARCHY_TEST_TIMEZONE="$1" OMARCHY_IMAGE_ROOT="$2" \
    OMARCHY_TEST_NOTIFICATION_ARGS="$notification_args" \
    bash -euo pipefail "$first_run_tz"
}
image="$test_tmp/image"
mkdir -p "$image/var/lib/omarchy/image" "$test_tmp/iso"
: >"$image/var/lib/omarchy/image/target.booted"

for zone in UTC ""; do
  run_timezone "$zone" "$image" || fail "unset timezone notification is accepted"
  grep -Fx '["omarchy-launch-floating-terminal-with-presentation","omarchy-menu-timezone"]' \
    "$notification_args" >/dev/null ||
    fail "timezone notification carries separate executable and argument"
done
pass "an image-built root on UTC sends an actionable notification through the real parser"

mv "$image/var/lib/omarchy/image/target.booted" "$image/var/lib/omarchy/image/target"
run_timezone UTC "$image" && [[ -e $notification_args ]] ||
  fail "an image root whose manifest is not retired yet is asked too"
pass "an image root whose manifest is not retired yet is asked too"

run_timezone Europe/London "$image"
[[ ! -e $notification_args ]] || fail "configured timezone sends no notification"
pass "configured timezone sends no notification"

for zone in UTC ""; do
  run_timezone "$zone" "$test_tmp/iso" || fail "an ISO install's first run succeeds"
  [[ ! -e $notification_args ]] || fail "an ISO install is never asked, even on UTC"
done
pass "an ISO install is never asked, even when its owner chose UTC"
