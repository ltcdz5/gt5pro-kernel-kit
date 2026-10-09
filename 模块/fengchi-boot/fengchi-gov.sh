#!/system/bin/sh
# 有游戏(game_opt 识别到) ⇒ scx（风驰）；无游戏 ⇒ uag（OPPO 官方默认 governor）。
# 注意：walt 是 Scene 的策略，不是官方默认；请不要在 Scene 里切换 CPU 调速器。
LOG=/data/adb/fengchi-gov.log
IDLE_GOV=uag
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
cur(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; }
has_scx(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null | tr ' ' '\n' | grep -qx scx; }
setgov(){ for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo "$1" > "$p" 2>/dev/null; done; }
log "daemon start (idle_gov=$IDLE_GOV)"
while true; do
  gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
  case "$gp" in *game_pid=-1*|"") game=0 ;; *) game=1 ;; esac
  if has_scx; then
    if [ "$game" = 1 ] && [ "$(cur)" != scx ]; then setgov scx; log "game -> $(cur)";
    elif [ "$game" = 0 ] && [ "$(cur)" != "$IDLE_GOV" ]; then setgov "$IDLE_GOV"; log "idle -> $(cur)"; fi
  fi
  sleep 4
done
