#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_刷入并验收.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt13 刷入 + 刷后验收（按 kernel-kit/opt13-刷机步骤-20261001.md 逐条执行）
set -u
ADB=/d/gaojizhushou/adb.exe
FB=/d/gaojizhushou/fastboot.exe
IMG=/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt13-repacked.img

echo "== 步骤1 进 fastboot $(date '+%H:%M:%S')"
"$ADB" reboot bootloader
sleep 10

echo "== 步骤2 等 fastboot 识别"
FOUND=0
for i in $(seq 1 25); do
  OUT=$("$FB" devices 2>&1)
  if echo "$OUT" | grep -qi "fastboot"; then echo "   $OUT"; FOUND=1; break; fi
  sleep 2
done
if [ "$FOUND" = 0 ]; then echo "!! 没识别到 fastboot 设备，停在这里（不猜）"; exit 1; fi

echo "== 步骤3 当前活动槽"
"$FB" getvar current-slot 2>&1

echo "== 步骤4 只刷 boot_a $(date '+%H:%M:%S')"
"$FB" flash boot_a "$IMG" 2>&1

echo "== 步骤5 显式钉回活动槽 a（fastboot 33.0.1 会顺手激活刚刷的槽）"
"$FB" set_active a 2>&1

echo "== 步骤6 重启 $(date '+%H:%M:%S')"
"$FB" reboot 2>&1
sleep 12
"$ADB" wait-for-device
echo "   设备回来了 $(date '+%H:%M:%S')"
for i in $(seq 1 100); do
  V=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$V" = "1" ] && { echo "   boot_completed=1（又 $((i*3))s）$(date '+%H:%M:%S')"; break; }
  sleep 3
done
sleep 45

echo "===== 验收7 横幅（期望 opt13 #33 22:10:10） ====="
"$ADB" shell "su -c 'uname -a'"
echo "===== 验收8 模块装载数（期望 621） ====="
"$ADB" shell "su -c 'lsmod | wc -l'"
echo "===== 验收9 装载失败类计数 ====="
"$ADB" shell "su -c 'dmesg | grep -c \"disagrees about version\"'"
"$ADB" shell "su -c 'dmesg | grep -ci \"module verification failed\"'"
echo "===== 验收10 MGLRU 三阶段是否复现 ====="
"$ADB" shell "su -c 'tail -6 /data/adb/lru_gen_on/state.log; echo 现值=; cat /sys/kernel/mm/lru_gen/enabled; cat /sys/kernel/mm/lru_gen/min_ttl_ms'"
echo "===== 验收11 内存与电量 ====="
"$ADB" shell "su -c 'head -q -n 3 /proc/meminfo | tr \"\\n\" \" \"; echo'"
"$ADB" shell "dumpsys battery | grep -m1 level"
echo "===== 附加：开机耗时与 SELinux ====="
"$ADB" shell "su -c 'getprop ro.boot.boottime; getprop sys.boot_completed; getenforce'"
echo done-marker
