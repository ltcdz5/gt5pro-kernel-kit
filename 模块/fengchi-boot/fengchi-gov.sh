#!/system/bin/sh
# 有游戏(game_opt 识别到) ⇒ scx；无游戏 ⇒ uag。每 4 秒轮询，幂等。
LOG=/data/adb/fengchi-gov.log
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
cur(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; }
has_scx(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null | tr ' ' '\n' | grep -qx scx; }
setgov(){ for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo "$1" > "$p" 2>/dev/null; done; }
log "daemon start"
while true; do
  gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
  case "$gp" in *game_pid=-1*|"") game=0 ;; *) game=1 ;; esac
  if has_scx; then
    if [ "$game" = 1 ] && [ "$(cur)" != scx ]; then setgov scx; log "game -> $(cur)"; 
    elif [ "$game" = 0 ] && [ "$(cur)" = scx ]; then setgov uag; log "idle -> $(cur)"; fi
  fi
  sleep 4
done
