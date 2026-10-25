#!/bin/bash
# Per-run diagnostics for the NFSU1 port, sourced by NFSU1.sh before the game starts.
# Everything the shell and the native process print is tee'd into a timestamped folder under logs/, so a
# crash that never reaches log.txt (a shell error, a signal, an OOM kill) still leaves a trail. On exit
# port_collect_exit copies the game logs and the kernel ring buffer next to it. GAMEDIR must be set.
PORT_RUN="$GAMEDIR/logs/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$PORT_RUN" || return 0
printf '%s\n' "$PORT_RUN" > "$GAMEDIR/logs/latest.txt"
# Keep only the 10 most recent run folders.
ls -1dt "$GAMEDIR"/logs/*/ 2>/dev/null | tail -n +11 | xargs -r rm -rf

exec > >(tee -a "$PORT_RUN/console.log") 2>&1

port_collect_exit() {
  local code="$1"
  printf '%s\n' "$code" > "$PORT_RUN/exit-code.txt"
  {
    date
    uname -a
    free -m
    for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq /sys/class/thermal/thermal_zone0/temp; do
      [ -f "$f" ] && echo "$f = $(cat "$f" 2>/dev/null)"
    done
  } > "$PORT_RUN/system.txt" 2>&1
  for f in log.txt log.prev.txt launcher.log update.log; do
    [ -f "$GAMEDIR/$f" ] && cp "$GAMEDIR/$f" "$PORT_RUN/$f"
  done
  dmesg > "$PORT_RUN/kernel.log" 2>&1 || true
  # A native signal (segfault, abort) shows as 128+signal; flag it for the user.
  if [ "$code" -gt 128 ] 2>/dev/null; then
    echo "The game stopped on signal $((code - 128)). See $PORT_RUN for logs." > "$GAMEDIR/LAST-CRASH.txt"
  fi
  sync
}
