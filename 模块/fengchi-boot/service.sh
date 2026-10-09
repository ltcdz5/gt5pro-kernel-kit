#!/system/bin/sh
# fengchi-boot：开机把风驰需要的东西准备好，然后启动守护
# ① 官方调度环境 ② 按依赖序加载厂商模块栈 ③ 恢复 MGLRU ④ 启动守护（PID 文件管理）

MODDIR=${0%/*}
LOGDIR=/sdcard/Download
LOG=$LOGDIR/fengchi-boot.log
PIDFILE=/data/adb/fengchi-gov.pid
M=/vendor_dlkm/lib/modules
mkdir -p "$LOGDIR" 2>/dev/null
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }
log "=== boot start ==="

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do sleep 2; i=$((i+1)); done

# ① 官方调度环境
setprop persist.sys.oplus.gameswitch.enable 1
setprop persist.sys.oiface.enable 1
setprop persist.sys.horae.enable 1
setprop sys.oplus.hmbird.manager.enable 1
start oiface 2>/dev/null
start horae 2>/dev/null
start gameopt_hal_service-1-0 2>/dev/null
start vendor.urcc-hal-aidl 2>/dev/null
log "env: gameswitch=$(getprop persist.sys.oplus.gameswitch.enable) oiface=$(getprop persist.sys.oiface.enable)"

# ② 厂商模块栈
for m in oplus_bsp_game_opt oplus_bsp_sched_assist oplus_bsp_sched_ext; do
  if [ "$(lsmod | grep -c "^$m")" = "0" ]; then
    k=$(find $M /vendor/lib/modules -name "$m.ko" 2>/dev/null | head -1)
    if [ -n "$k" ]; then insmod "$k"; log "insmod $m rc=$?"; fi
  fi
done
log "stack: game_opt=$(lsmod | grep -c '^oplus_bsp_game_opt') sched_ext=$(lsmod | grep -c '^oplus_bsp_sched_ext')"

# ③ MGLRU
if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
  echo Y > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
  [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ] && echo 1000 > /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null
  log "mglru: enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null) min_ttl_ms=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)"
fi

# ④ 停掉旧守护（按 PID 文件，快），再启动新守护
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ]; then kill -9 "$old" 2>/dev/null; log "killed old daemon pid=$old"; fi
  rm -f "$PIDFILE" 2>/dev/null
fi
sleep 1
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 < /dev/null &
else
  nohup sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 < /dev/null &
fi
sleep 3
if [ -f "$PIDFILE" ]; then log "governor daemon started pid=$(cat $PIDFILE)"; else log "governor daemon NOT started"; fi
log "=== boot done ==="