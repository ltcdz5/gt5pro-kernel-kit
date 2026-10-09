#!/system/bin/sh
# fengchi-boot 守护：检测到游戏就切 scx + 开 ctb；离开游戏满 IDLE_DELAY 秒后切回并还原
MODDIR=${0%/*}
[ -f "$MODDIR/fengchi.conf" ] && . "$MODDIR/fengchi.conf"
[ -z "$IDLE_GOV" ] && IDLE_GOV=uag
[ -z "$SCX_GOV" ] && SCX_GOV=scx
[ -z "$POLL_SEC" ] && POLL_SEC=4
[ -z "$LOG_DIR" ] && LOG_DIR=/sdcard/Download
[ -z "$LOG_MAX" ] && LOG_MAX=2000
[ -z "$CTB" ] && CTB=1
[ -z "$IDLE_DELAY" ] && IDLE_DELAY=10
[ -z "$HEARTBEAT_MIN" ] && HEARTBEAT_MIN=30
LOG=$LOG_DIR/fengchi-gov.log
PIDFILE=/data/adb/fengchi-gov.pid
CTB_NODE=/proc/game_opt/task_boost/ct_enable
CTB_ORIG=/data/adb/fengchi-ctb.orig
mkdir -p $LOG_DIR 2>/dev/null

# ---- 单实例保护 ----
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
ctb_on(){
  [ "$CTB" = "1" ] || return 0
  [ -w "$CTB_NODE" ] || return 0
  v=$(cat "$CTB_NODE" 2>/dev/null)
  if [ "$v" != "1" ]; then
    [ -f "$CTB_ORIG" ] || echo "$v" > "$CTB_ORIG" 2>/dev/null
    echo 1 > "$CTB_NODE" 2>/dev/null && log "ctb -> 1 (was $v)"
  fi
}
ctb_off(){
  [ "$CTB" = "1" ] || return 0
  [ -f "$CTB_ORIG" ] || return 0
  o=$(cat "$CTB_ORIG" 2>/dev/null)
  if [ -w "$CTB_NODE" ] && [ "$(cat $CTB_NODE 2>/dev/null)" != "$o" ]; then
    echo "$o" > "$CTB_NODE" 2>/dev/null
    log "ctb -> $o (还原)"
  fi
  rm -f "$CTB_ORIG" 2>/dev/null
}

# 开机先清残留（上次异常退出可能留下 ct_enable=1）
if [ -f "$CTB_ORIG" ]; then
  ctb_off
  log "启动清理：还原上次残留的 ct_enable"
fi

IDLE_TICKS=0
HB=0
log "daemon start pid=$$ (idle=$IDLE_GOV scx=$SCX_GOV poll=$POLL_SEC ctb=$CTB delay=$IDLE_DELAY)"
while true; do
  gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
  case "$gp" in *game_pid=-1*|"") game=0 ;; *) game=1 ;; esac
  if has_gov "$SCX_GOV"; then
    if [ "$game" = 1 ]; then
      IDLE_TICKS=0
      [ "$(cur)" != "$SCX_GOV" ] && { setgov "$SCX_GOV"; log "game -> $(cur)"; }
      ctb_on
    else
      if [ "$(cur)" = "$SCX_GOV" ] || [ -f "$CTB_ORIG" ]; then
        IDLE_TICKS=$((IDLE_TICKS + POLL_SEC))
        if [ $IDLE_TICKS -ge $IDLE_DELAY ]; then
          [ -n "$IDLE_GOV" ] && [ "$(cur)" = "$SCX_GOV" ] && { setgov "$IDLE_GOV"; log "idle($IDLE_TICKS)s -> $(cur)"; }
          ctb_off
        fi
      fi
    fi
  fi
  if [ "$HEARTBEAT_MIN" -gt 0 ] 2>/dev/null; then
    HB=$((HB + POLL_SEC))
    if [ $HB -ge $((HEARTBEAT_MIN * 60)) ]; then
      HB=0
      log "heartbeat: 运行中 ｜ 调速器=$(cur) ｜ game=$game ｜ ctb=$(cat $CTB_NODE 2>/dev/null)"
    fi
  fi
  sleep "$POLL_SEC"
done