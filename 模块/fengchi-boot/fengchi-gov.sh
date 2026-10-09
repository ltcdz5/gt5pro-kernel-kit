#!/system/bin/sh
# fengchi-boot 守护：检测到游戏就切到 scx，退出游戏就切回官方默认
# 日志写到 $LOG_DIR/fengchi-gov.log（默认 /sdcard/Download）

MODDIR=${0%/*}
[ -f "$MODDIR/fengchi.conf" ] && . "$MODDIR/fengchi.conf"
[ -z "$IDLE_GOV" ] && IDLE_GOV=uag
[ -z "$SCX_GOV" ] && SCX_GOV=scx
[ -z "$POLL_SEC" ] && POLL_SEC=4
[ -z "$LOG_DIR" ] && LOG_DIR=/sdcard/Download
[ -z "$LOG_MAX" ] && LOG_MAX=2000
LOG=$LOG_DIR/fengchi-gov.log
PIDFILE=/data/adb/fengchi-gov.pid
mkdir -p $LOG_DIR 2>/dev/null

# ---- 单实例保护：已有实例就直接退出 ----
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    c=$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)
    case "$c" in *fengchi-gov*) exit 0 ;; esac
  fi
fi
echo $$ > "$PIDFILE" 2>/dev/null

log(){
  echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
  n=$(wc -l < "$LOG" 2>/dev/null)
  if [ -n "$n" ] && [ "$n" -gt "$LOG_MAX" ] 2>/dev/null; then
    tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
  fi
}
cur(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; }
has_gov(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
setgov(){ for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo "$1" > "$p" 2>/dev/null; done; }

log "daemon start pid=$$ (idle=$IDLE_GOV scx=$SCX_GOV poll=$POLL_SEC)"
while true; do
  gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
  case "$gp" in *game_pid=-1*|"") game=0 ;; *) game=1 ;; esac
  if has_gov "$SCX_GOV"; then
    if [ "$game" = 1 ] && [ "$(cur)" != "$SCX_GOV" ]; then
      setgov "$SCX_GOV"; log "game -> $(cur)"
    elif [ "$game" = 0 ] && [ -n "$IDLE_GOV" ] && [ "$(cur)" = "$SCX_GOV" ]; then
      setgov "$IDLE_GOV"; log "idle -> $(cur)"
    fi
  fi
  sleep "$POLL_SEC"
done