#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/io_bench2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# I/O 对照 v2 —— 小样本 + 先标定噪声带, 只有档间中位数差 > 噪声带才算差异
# 总量约 5GB(上一版 24GB)。全部运行时值, 结束还原。
ADB="D:/gaojizhushou/adb.exe"
Q=/sys/block/sda/queue
F=/data/local/tmp/iob2.bin
SZ=128
LOG=/c/Users/USERNAME/Desktop/gt5pro-kernel/logs/io-bench2.txt
: > "$LOG"
r() { $ADB shell "su -c '$1'" 2>&1 | tr -d '\r' | tail -1; }

ms() { r "t0=\$(date +%s%N); $1; t1=\$(date +%s%N); echo \$(( (t1-t0)/1000000 ))"; }
rd() { r "sync; echo 3 > /proc/sys/vm/drop_caches; t0=\$(date +%s%N); toybox dd if=$F of=/dev/null bs=1M count=$SZ status=none; t1=\$(date +%s%N); echo \$(( (t1-t0)/1000000 ))"; }
wr() { r "t0=\$(date +%s%N); toybox dd if=/dev/zero of=$F bs=1M count=$SZ conv=fsync status=none; t1=\$(date +%s%N); echo \$(( (t1-t0)/1000000 ))"; }

echo "=== 前置 ==="
r "cat /proc/loadavg" | sed 's/^/  loadavg: /'
r "toybox dd if=/dev/zero of=$F bs=1M count=$SZ status=none" >/dev/null

echo "=== P0 噪声标定: mq-deadline + ra512 读 x5 ===" 2>&1 | tee -a "$LOG"
r "echo mq-deadline > $Q/scheduler; echo 512 > $Q/read_ahead_kb" >/dev/null
for i in 1 2 3 4 5; do v=$(rd); echo "  p0-$i 读=${v}ms" | tee -a "$LOG"; done

echo "=== P1 写: 4 调度器 x3 (交替) ===" 2>&1 | tee -a "$LOG"
for i in 1 2 3; do for s in mq-deadline kyber bfq none; do r "echo $s > $Q/scheduler" >/dev/null
  v=$(wr); echo "  w$i $s ${v}ms" | tee -a "$LOG"; done; done

echo "=== P2 读: mq-deadline/kyber x ra(128,512,1024) x4 (交替) ===" 2>&1 | tee -a "$LOG"
for i in 1 2 3 4; do for s in mq-deadline kyber; do for ra in 128 512 1024; do
  r "echo $s > $Q/scheduler; echo $ra > $Q/read_ahead_kb" >/dev/null
  v=$(rd); echo "  r$i $s ra=$ra ${v}ms" | tee -a "$LOG"; done; done; done

echo "=== 还原 ===" 2>&1 | tee -a "$LOG"
r "echo mq-deadline > $Q/scheduler; echo 512 > $Q/read_ahead_kb; rm -f $F; cat $Q/scheduler; cat $Q/read_ahead_kb" | tee -a "$LOG"
echo "存档 $LOG"
