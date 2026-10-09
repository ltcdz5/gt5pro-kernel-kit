#!/system/bin/sh
# fengchi-boot v1.1 —— 自编内核专用：让风驰(scx)自动就绪 + MGLRU 恢复
# 只做三件事，全部幂等；日志 /data/adb/fengchi-boot.log
MODDIR=${0%/*}
LOG=/data/adb/fengchi-boot.log
M=/vendor_dlkm/lib/modules
log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 等开机完成
i=0; while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do sleep 2; i=$((i+1)); done

# 1) 官调总闸（风驰依赖完整官调环境；同时覆盖原 horae_once 的作用）
setprop persist.sys.oplus.gameswitch.enable 1
setprop persist.sys.oiface.enable 1
setprop persist.sys.horae.enable 1
setprop sys.oplus.hmbird.manager.enable 1
start oiface 2>/dev/null; start horae 2>/dev/null
start gameopt_hal_service-1-0 2>/dev/null; start vendor.urcc-hal-aidl 2>/dev/null
log "env: gameswitch=$(getprop persist.sys.oplus.gameswitch.enable) horae=$(getprop persist.sys.horae.enable)"

# 2) 按依赖序加载厂商栈（scx 调速器由 sched_ext 注册）
for m in oplus_bsp_game_opt oplus_bsp_sched_assist oplus_bsp_sched_ext; do
  if [ "$(lsmod | grep -c "^$m")" = "0" ]; then
    k=$(find $M /vendor/lib/modules -name "$m.ko" 2>/dev/null | head -1)
    [ -n "$k" ] && { insmod "$k"; log "insmod $m rc=$?"; }
  fi
done
log "stack: game_opt=$(lsmod | grep -c '^oplus_bsp_game_opt') sched_ext=$(lsmod | grep -c '^oplus_bsp_sched_ext')"

# 3) MGLRU 运行时值恢复（原 lru_gen_on 的作用，并入本模块）
if [ -w /sys/kernel/mm/lru_gen/enabled ]; then
  echo Y > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
  [ -w /sys/kernel/mm/lru_gen/min_ttl_ms ] && echo 1000 > /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null
  log "mglru: enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null) min_ttl_ms=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)"
fi

# 4) 起调速器守护
[ -f "$MODDIR/fengchi-gov.sh" ] && { pkill -f fengchi-gov.sh 2>/dev/null; nohup sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 & log "governor daemon started"; }
