#!/system/bin/sh
# fengchi-boot：开机准备风驰所需环境，然后交给看门狗托管守护
# ① 官方调度环境 ② 厂商模块栈 ③ MGLRU ④ 关键线程通路(可选) ⑤ 启动看门狗(守护由它托管)

MODDIR=${0%/*}
[ -f "$MODDIR/fengchi.conf" ] && . "$MODDIR/fengchi.conf"
[ -z "$OPGS" ] && OPGS=1
[ -z "$LOG_DIR" ] && LOG_DIR=/sdcard/Download
LOGDIR=$LOG_DIR
LOG=$LOGDIR/fengchi-boot.log
GPID=/data/adb/fengchi-gov.pid
WPID=/data/adb/fengchi-watch.pid
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

# ② 厂商模块栈（依赖序；scx 调速器由最后那个注册）
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
  log "mglru: enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null)"
fi

# ④ 关键线程通路（可选，检测到第三方组件才拉起）
if [ "$OPGS" = "1" ]; then
  O=/data/adb/modules/scrc/kmodule/service.sh
  if [ -f "$O" ]; then
    sh "$O" >> "$LOG" 2>&1 &
    j=0
    while [ ! -e /proc/game_opt/task_boost/critical_task_name ] && [ $j -lt 15 ]; do sleep 1; j=$((j+1)); done
    if [ -e /proc/game_opt/task_boost/critical_task_name ]; then
      log "ctn: 节点就绪 (ctn_patch=$(lsmod | grep -c ctn_patch))"
    else
      log "ctn: 节点未出现（可能内核版本不匹配）"
    fi
  else
    log "ctn: 未安装第三方关键线程组件，跳过（不影响风驰切换）"
  fi
fi

# ⑤ 停掉旧的看门狗/守护，再启动看门狗（守护由它托管、挂了会自动重启）
for f in $WPID $GPID; do
  if [ -f "$f" ]; then
    p=$(cat "$f" 2>/dev/null)
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    rm -f "$f" 2>/dev/null
  fi
done
sleep 1
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$MODDIR/fengchi-watch.sh" >/dev/null 2>&1 < /dev/null &
else
  nohup sh "$MODDIR/fengchi-watch.sh" >/dev/null 2>&1 < /dev/null &
fi
sleep 4
if [ -f "$GPID" ]; then log "governor daemon started pid=$(cat $GPID)"; else log "governor daemon NOT started"; fi
if [ -f "$WPID" ]; then log "watchdog started pid=$(cat $WPID)"; else log "watchdog NOT started"; fi
log "=== boot done ==="