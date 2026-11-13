#!/bin/sh
# Preview the working tree's Waterfox build in a headless sway, for screenshots.
#
#   preview.sh start <dir> [host]   build <host>'s (default hestia) HM generation,
#                                   start headless sway + waterfox, record PIDs in <dir>
#   preview.sh shot  <dir> <name>   grim the headless output to <dir>/<name>.png
#   preview.sh stop  <dir>          kill waterfox, then sway, by their recorded PIDs
#   preview.sh live  <dir>          same build on the real display (WAYLAND_DISPLAY), for review
#
# <dir> is scratch space (the agent's scratchpad). The profile is throwaway: the
# generation's user.js + userChrome.css plus a copy of the live prefs.js
# (toolbar placements, sidebar state; a bare profile behaves like a first run).
# Never kill waterfox or sway by name or a globbed socket: the user's own
# session runs alongside.
set -eu
cmd=$1
dir=$2
mkdir -p "$dir"
repo=$(cd "$(dirname "$0")/../../.." && pwd)

build() {
  nix build "$repo#nixosConfigurations.${1:-hestia}.config.home-manager.users.dk.home.activationPackage" \
    --no-link --print-out-paths > "$dir/gen"
}

launch() { # <WAYLAND_DISPLAY>
  gen=$(cat "$dir/gen")
  p=$dir/profile
  rm -rf "$p"
  mkdir -p "$p/chrome"
  cp ~/.config/waterfox/default/prefs.js "$p/prefs.js"
  cp -L "$gen/home-files/.config/waterfox/default/user.js" "$p/user.js"
  cp -L "$gen/home-files/.config/waterfox/default/chrome/userChrome.css" "$p/chrome/userChrome.css"
  chmod -R u+w "$p"
  env -u DISPLAY WAYLAND_DISPLAY="$1" MOZ_ENABLE_WAYLAND=1 \
    setsid "$gen/home-path/bin/waterfox" --new-instance --no-remote --profile "$p" https://example.com \
    > "$dir/wf.log" 2>&1 < /dev/null &
  echo $! > "$dir/wf.pid"
}

stop_pid() { # <pidfile>
  [ -f "$1" ] || return 0
  pid=$(cat "$1")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    timeout 15 sh -c "while kill -0 $pid 2>/dev/null; do sleep 0.5; done"
  fi
  rm -f "$1"
}

case $cmd in
  start)
    build "${3:-hestia}"
    printf 'output HEADLESS-1 resolution 1600x1000 scale 1\ndefault_border none\nexec sh -c '\''echo $WAYLAND_DISPLAY > %s/display'\''\n' \
      "$dir" > "$dir/sway.conf"
    rm -f "$dir/display"
    env -u SWAYSOCK -u WAYLAND_DISPLAY -u DISPLAY \
      WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
      setsid sway -c "$dir/sway.conf" > "$dir/sway.log" 2>&1 < /dev/null &
    echo $! > "$dir/sway.pid"
    timeout 15 sh -c "until [ -s '$dir/display' ]; do sleep 0.5; done"
    launch "$(cat "$dir/display")"
    sock=/run/user/$(id -u)/sway-ipc.$(id -u).$(cat "$dir/sway.pid").sock
    timeout 30 sh -c "until SWAYSOCK=$sock swaymsg -t get_tree | grep -q '\"app_id\": \"waterfox\"'; do sleep 1; done"
    sleep 6 # first paint, add-on install tabs
    echo "sway $(cat "$dir/sway.pid") waterfox $(cat "$dir/wf.pid") on $(cat "$dir/display")"
    ;;
  shot)
    WAYLAND_DISPLAY=$(cat "$dir/display") nix-shell -p grim --run "grim '$dir/$3.png'"
    echo "$dir/$3.png"
    ;;
  stop)
    stop_pid "$dir/wf.pid"
    stop_pid "$dir/sway.pid"
    ;;
  live)
    stop_pid "$dir/wf.pid"
    build "${3:-hestia}"
    launch "$WAYLAND_DISPLAY"
    echo "waterfox $(cat "$dir/wf.pid") on $WAYLAND_DISPLAY"
    ;;
  *)
    echo "usage: $0 start|shot|stop|live <dir> ..." >&2
    exit 2
    ;;
esac
