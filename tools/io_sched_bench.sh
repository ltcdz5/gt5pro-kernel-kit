#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/io_sched_bench.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 运行时 I/O 对照: 4 个调度器 x (写 / 3 档 read_ahead 读), 交替 3 轮, 测完还原
# 零刷机、全部 sysfs 运行时值、结束还原原样
ADB="D:/gaojizhushou/adb.exe"
F=/data/local/tmp/iobench.bin
LOG=/c/Users/xutengfa/Desktop/gt5pro-kernel/logs/io-sched-bench.txt
: > "$LOG"
run() { $ADB shell "su -c '$1'" 2>&1 | tr -d '\r'; }

echo "=== 准备 ==="
run "svc power stayon true; sync; echo 3 > /proc/sys/vm/drop_caches"
run "toybox dd if=/dev/zero of=$F bs=1M count=512 status=none && ls -l $F" | tail -1

SCHED="mq-deadline kyber bfq none"
RAS="128 512 1024"
printf "%-8s %-12s %-10s %s\n" 轮 调度器 ra_kb 结果 > "$LOG"
for r in 1 2 3; do
  for s in $SCHED; do
    run "echo $s > /sys/block/sda/queue/scheduler; cat /sys/block/sda/queue/scheduler" >/dev/null
    cur=$(run "cut -d' ' -f1 /sys/block/sda/queue/scheduler | tr -d '['" )
    # 写测(512MB, fsync)
    w=$(run "sync; t0=\$(date +%s%N); toybox dd if=/dev/zero of=$F bs=1M count=512 conv=fsync status=none; t1=\$(date +%s%N); echo \$(( (t1-t0)/1000000 ))")
    printf "%-8s %-12s %-10s 写=%sms\n" "$r" "$s" "-" "$w" | tee -a "$LOG"
    for ra in $RAS; do
      run "echo $ra > /sys/block/sda/queue/read_ahead_kb; sync; echo 3 > /proc/sys/vm/drop_caches" >/dev/null
      rd=$(run "t0=\$(date +%s%N); toybox dd if=$F of=/dev/null bs=1M status=none; t1=\$(date +%s%N); echo \$(( (t1-t0)/1000000 ))")
      printf "%-8s %-12s %-10s 读=%sms\n" "$r" "$s" "$ra" "$rd" | tee -a "$LOG"
    done
  done
done

echo "=== 还原 ==="
run "echo mq-deadline > /sys/block/sda/queue/scheduler; echo 512 > /sys/block/sda/queue/read_ahead_kb; rm -f $F; svc power stayon false; cat /sys/block/sda/queue/scheduler; cat /sys/block/sda/queue/read_ahead_kb" | tail -2
echo "存档: $LOG"
