#!/system/bin/sh
# fengchi-boot 看门狗 v2.6：守护意外退出【或活着但卡住】就重启（自身保证单实例）
#   ★v2.6（t125）★：本轮只补守护的 D4 版本闸门与 F1 双源解析，
#   看门狗逻辑与 v2.5 完全相同（D9 的心跳判据 + kill -9 + 退避上限），仅版本串随包更新。
# ★v2.5 修复 D9★：v2.4 只看 /proc/<pid> 目录 + cmdline ⇒ 进程活着但卡住时永不重启。
#   现增加：① 心跳文件时效判据（守护每轮写 /data/adb/fengchi-gov.beat）
#           ② 卡死时先 kill -9 再重启  ③ 重启退避与上限（坏 conf 不会被每 20s 无限拉起）
MODDIR=${0%/*}
[ -f "$MODDIR/fengchi.conf" ] && . "$MODDIR/fengchi.conf"
[ -z "$LOG_DIR" ] && LOG_DIR=/sdcard/Download
[ -z "$POLL_SEC" ] && POLL_SEC=4
WATCH_PID=/data/adb/fengchi-watch.pid
GPID=/data/adb/fengchi-gov.pid
BEAT=/data/adb/fengchi-gov.beat
LOG=$LOG_DIR/fengchi-gov.log
RESTART_WIN=600
RESTART_MAX=5
BEAT_TIMEOUT=$((POLL_SEC * 3))
[ "$BEAT_TIMEOUT" -lt 30 ] && BEAT_TIMEOUT=30
BC=0
RCOUNT=0
LAST_RESTART=0
mkdir -p "$LOG_DIR" 2>/dev/null
wlog(){ echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }
# 单实例（D10：不再静默）
if [ -f "$WATCH_PID" ]; then
  old=$(cat "$WATCH_PID" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    c=$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)
    case "$c" in *fengchi-watch*) wlog "watchdog already running (pid=$old) => exit"; exit 0 ;; esac
  fi
fi
echo $$ > "$WATCH_PID" 2>/dev/null
wlog "watchdog start v2.7 pid=$$ (beat_timeout=${BEAT_TIMEOUT}s restart_max=$RESTART_MAX/${RESTART_WIN}s)"
start_gov(){
  rm -f "$GPID" 2>/dev/null
  wlog "watchdog: 重启守护（第 $RCOUNT 次 / ${RESTART_WIN}s 窗口内）"
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 < /dev/null &
  else
    nohup sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 < /dev/null &
  fi
}
while true; do
  alive=0; stuck=0
  if [ -f "$GPID" ]; then
    p=$(cat "$GPID" 2>/dev/null)
    if [ -n "$p" ] && [ -d "/proc/$p" ]; then
      c=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
      case "$c" in *fengchi-gov*) alive=1 ;; esac
    fi
  fi
  now=$(date +%s 2>/dev/null)
  if [ "$alive" = "1" ]; then
    b=$(cat "$BEAT" 2>/dev/null)
    if [ -n "$b" ] && [ -n "$now" ]; then
      age=$((now - b))
      if [ "$age" -gt "$BEAT_TIMEOUT" ] 2>/dev/null; then stuck=1; fi
    elif [ -n "$now" ]; then
      # 心跳文件不存在：给守护一个宽限期（可能刚起），第二次仍无则算卡死
      BC=$((BC + 1))
      if [ "$BC" -gt 1 ]; then stuck=1; fi
    fi
  fi
  if [ "$alive" = "0" ] || [ "$stuck" = "1" ]; then
    if [ "$stuck" = "1" ]; then
      wlog "watchdog: 守护卡死（心跳=[$(cat $BEAT 2>/dev/null)] now=$now timeout=$BEAT_TIMEOUT）=> kill -9 $p 后重启"
      [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    else
      wlog "watchdog: 守护不在，正在重启"
    fi
    if [ -n "$now" ] && [ "$LAST_RESTART" != "0" ] && [ $((now - LAST_RESTART)) -lt "$RESTART_WIN" ]; then
      RCOUNT=$((RCOUNT + 1))
    else
      RCOUNT=1
    fi
    [ -n "$now" ] && LAST_RESTART=$now
    if [ "$RCOUNT" -gt "$RESTART_MAX" ]; then
      wlog "watchdog: 重启过于频繁（$RCOUNT > $RESTART_MAX / ${RESTART_WIN}s），冷却 300s 后重置计数"
      sleep 300
      RCOUNT=0
    else
      start_gov
      sleep 5
    fi
  fi
  sleep 20
done
