# The ISO, or the owner setup a deferred install finishes on first boot, asks
# for a timezone. A prebuilt image may boot on UTC with nobody asked and keep it
# until somebody notices. First run is a graphical session with nowhere to ask,
# so notify and open the timezone menu.

current_timezone() {
  timedatectl show --property=Timezone --value 2>/dev/null
}

# The image manifest, retired or not, records that this root was built as an
# image (install/helpers/image-target.sh). Only there does UTC stand in for
# "nobody has chosen yet": someone who picked UTC on the ISO is never asked.
image_built() {
  local image_dir=${OMARCHY_IMAGE_ROOT:-}/var/lib/omarchy/image
  [[ -e $image_dir/target || -e $image_dir/target.booted ]]
}

timezone_needs_setting() {
  image_built || return 1
  timezone=$(current_timezone)
  [[ -z $timezone || $timezone == "UTC" ]]
}

if timezone_needs_setting; then
  if [[ -n $timezone ]]; then
    message="This machine is on $timezone. Click to choose yours."
  else
    message="This machine has no timezone set. Click to choose yours."
  fi
  omarchy-notification-send -u critical -g 󰥔 "Set your timezone" "$message" \
    --exec omarchy-launch-floating-terminal-with-presentation omarchy-menu-timezone
fi
