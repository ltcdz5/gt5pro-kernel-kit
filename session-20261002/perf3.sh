#!/bin/bash
# P3: 关闭有运行时开销的调试开关 (社区清单里的"关闭部分调试选项，减少性能开销")
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
OUT=/home/builder/perf3
mkdir -p "$OUT"
cd "$K" || exit 1

{
echo "=== 0) 起点 ==="
echo "  HEAD: $(git rev-parse --short HEAD)  工作区改动: $(git status --porcelain | wc -l)"
cp -f out/.config "$OUT/.config.before-p3"
echo "  config 已备份 (P2 状态)"
echo
echo "=== 1) 关掉有运行时开销的调试项 ==="
CFG=out/.config
./scripts/config --file $CFG \
  -d SCHEDSTATS \
  -d SCHED_INFO \
  -d RCU_TRACE \
  -d KFENCE \
  -d DEBUG_LIST \
  -d SOFTLOCKUP_DETECTOR \
  -d DETECT_HUNG_TASK 2>&1 | tail -3
echo "  --- 复核 ---"
grep -E '^CONFIG_(SCHEDSTATS|SCHED_INFO|RCU_TRACE|KFENCE|DEBUG_LIST|SOFTLOCKUP_DETECTOR|DETECT_HUNG_TASK|SCHED_DEBUG)=' $CFG
echo
echo "=== 2) olddefconfig ==="
make -s LLVM=1 ARCH=arm64 O=out olddefconfig 2>&1 | tail -3
grep -E '^CONFIG_(SCHEDSTATS|SCHED_INFO|RCU_TRACE|KFENCE|DEBUG_LIST|SOFTLOCKUP_DETECTOR|DETECT_HUNG_TASK|SCHED_DEBUG|HZ)=' $CFG
} > "$OUT/log.txt" 2>&1

ACKN=138
NEXT=$(( $(cat out/.version 2>/dev/null || echo 46) + 1 ))
BV="${NEXT}-ack${ACKN}-p3"

{
echo
echo "=== 3) 构建  KBUILD_BUILD_VERSION=$BV ==="
date
} >> "$OUT/log.txt" 2>&1

make -k -j"$(nproc)" LLVM=1 ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- \
  'CC=ccache clang' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out \
  KBUILD_BUILD_VERSION="$BV" \
  KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image > "$OUT/make.log" 2>&1
rc=$?
{
echo "  make rc=$rc  错误行=$(grep -cE 'error:' "$OUT/make.log" || true)"
date
} >> "$OUT/log.txt" 2>&1

if [ "$rc" -ne 0 ]; then
  { echo "  --- 错误前 30 条 ---"; grep -E 'error:' "$OUT/make.log" | head -30; } >> "$OUT/log.txt" 2>&1
  exit 1
fi

{
echo
echo "=== 4) 归档 + 双闸门 ==="
cp -f out/arch/arm64/boot/Image "$OUT/Image.p3"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.p3"
echo "  Image md5 = $(md5sum "$OUT/Image.p3" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.p3")   (P2 = 36915712)"
echo "  横幅 = $(strings "$OUT/Image.p3" | grep -oE '[0-9]+-ack[0-9]+-p3 SMP PREEMPT[^\"]{0,30}' | head -1)"
echo
echo "  --- 闸门1 导出集合 ---"
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py out/vmlinux.symvers
echo "  rc=$?"
echo "  --- 闸门2 厂商 CRC 真值 ---"
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_vko_crc.py out/vmlinux.symvers \
  /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm \
  /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/system_dlkm
echo "  rc=$?"
echo "=== 完成 ==="
} >> "$OUT/log.txt" 2>&1
