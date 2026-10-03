#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存4_runner.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# v4 正规 runner：每轮 先重启 → 轮询到 sys.boot_completed=1 → 同步跑一轮 → 确认收尾标记 → 下一轮
# 顺序：先关(N) 后开(Y)，与上一晚的 A→B 相反，用来消掉顺序 confound
ADB=/d/gaojizhushou/adb.exe
OUT=/c/Users/USERNAME/Downloads/v4
mkdir -p "$OUT"

wait_boot() {
  for i in $(seq 1 100); do
    if "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -qx 1; then
      echo "    boot_completed=1（等了约 $((i*3))s）"
      return 0
    fi
    sleep 3
  done
  echo "    超时：等不到 boot_completed"
  return 1
}

run_round() {
  TAG="$1"; STATE="$2"
  echo "===== $TAG 设定 MGLRU=$STATE：重启归一化 $(date +%H:%M:%S)"
  "$ADB" reboot
  sleep 8                      # 等 USB 断开，避免轮询打到旧会话
  wait_boot || return 1
  "$ADB" shell "su -c 'sh /data/local/tmp/lx4.sh $TAG $STATE 40 120'" > "$OUT/$TAG.txt" 2>&1
  if grep -q "^done$" "$OUT/$TAG.txt"; then
    echo "    本轮完整结束"
  else
    echo "    ⚠ 本轮没跑到收尾，结果作废："
    tail -3 "$OUT/$TAG.txt"
    return 1
  fi
  grep -E "设定后 enabled=|实际启动成功|==== 结果|消失清单|本轮墙钟|pgmajfault|refault|pgscan|am_kill|PSI" "$OUT/$TAG.txt" | sed 's/^/    /'
}

run_round B1_off N
R1=$?
run_round A1_on Y
R2=$?
echo "===== 完成 B1=$R1 A1=$R2 （0=成功）"
"$ADB" shell "su -c 'dumpsys battery | grep -m1 level'"
