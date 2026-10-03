#!/bin/bash
# P4 = P2(138条 + 10项社区config) + ThinLTO
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
OUT=/home/builder/perf4
mkdir -p "$OUT"
cd "$K" || exit 1

{
echo "=== 0) 起点 ==="
echo "  HEAD: $(git rev-parse --short HEAD)  工作区改动: $(git status --porcelain | wc -l)"
cp -f out/.config "$OUT/.config.before-p4"
echo "  当前 config = P2 状态 (HZ300 + 社区10项, 无LTO)"
grep -E '^CONFIG_(HZ|LTO_NONE|LTO_CLANG_THIN|CRYPTO_SHA256_ARM64_CE)=' out/.config
echo
echo "=== 1) 加回 ThinLTO ==="
./scripts/config --file out/.config -e LTO_CLANG -e LTO_CLANG_THIN -d LTO_NONE 2>&1 | tail -2
make -s LLVM=1 ARCH=arm64 O=out olddefconfig 2>&1 | tail -2
echo "  --- 复核 ---"
grep -E '^CONFIG_(LTO|LTO_CLANG|LTO_CLANG_THIN|LTO_CLANG_FULL|LTO_NONE|HZ|CRYPTO_SHA256_ARM64_CE|SCHEDSTATS|DEBUG_LIST)=' out/.config
echo
echo "=== 2) 守卫 ==="
if grep -q '^CONFIG_LTO_CLANG_THIN=y' out/.config && grep -q '^CONFIG_HZ=300' out/.config \
   && grep -q '^CONFIG_SCHEDSTATS=y' out/.config && grep -q '^CONFIG_DEBUG_LIST=y' out/.config; then
  echo "  ✅ LTO开 + HZ300 + 调试项保持原样(perf3的坑已避开)"
else
  echo "  ★ 守卫失败, 中止"; exit 3
fi
} > "$OUT/log.txt" 2>&1

ACKN=138
NEXT=$(( $(cat out/.version 2>/dev/null || echo 46) + 1 ))
BV="${NEXT}-ack${ACKN}-p4"

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
cp -f out/arch/arm64/boot/Image "$OUT/Image.p4"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.p4"
echo "  Image md5 = $(md5sum "$OUT/Image.p4" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.p4")   (P2 = 36915712, opt15c = 36841984)"
echo "  横幅 = $(strings "$OUT/Image.p4" | grep -oE '[0-9]+-ack[0-9]+-p4 SMP PREEMPT[^\"]{0,30}' | head -1)"
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
