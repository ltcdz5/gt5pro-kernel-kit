#!/bin/bash
# P2: 社区验证的纯 config 增量 (CRC 中性), 退回无 LTO
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
OUT=/home/builder/perf2
mkdir -p "$OUT"
cd "$K" || exit 1

{
echo "=== 0) 起点 ==="
echo "  HEAD: $(git rev-parse --short HEAD)  工作区改动: $(git status --porcelain | wc -l)"
echo
echo "=== 1) 恢复 opt15c 的 config (退掉 LTO) ==="
cp -f /home/builder/perf1/.config.before out/.config
grep -E '^CONFIG_(LTO|LTO_CLANG|LTO_CLANG_THIN|LTO_NONE)=' out/.config
echo
echo "=== 2) 确认 LLVM_POLLY 在 Makefile 里怎么生效 ==="
grep -n -B2 -A4 'LLVM_POLLY' Makefile | head -20
echo
echo "=== 3) 注入社区 config 增量 ==="
CFG=out/.config
./scripts/config --file $CFG \
  -d HZ_250 -e HZ_300 --set-val HZ 300 \
  -e LLVM_POLLY \
  -e CRYPTO_SHA256_ARM64_CE -e CRYPTO_SHA3_ARM64 -e CRYPTO_AES_ARM64_CE_CCM \
  -e CRYPTO_SM3_ARM64_CE -e CRYPTO_SM4_ARM64_CE -e CRYPTO_SM4_ARM64_CE_BLK \
  -e SLAB_MERGE_DEFAULT \
  -e EROFS_FS_ZIP_LZMA -e EROFS_FS_ZIP_DEFLATE \
  -e RCU_NOCB_CPU_DEFAULT_ALL -e RCU_NOCB_CPU_CB_BOOST \
  -e NET_SCH_ETS -e NET_SCH_PIE \
  -e SECURITY_LANDLOCK \
  -e SECTION_MISMATCH_WARN_ONLY \
  -e ZRAM_MEMORY_TRACKING \
  -e AUTOFDO_CLANG 2>&1 | tail -5
echo "  --- 复核 ---"
grep -E '^CONFIG_(HZ|HZ_250|HZ_300|LLVM_POLLY|CRYPTO_SHA256_ARM64_CE|CRYPTO_SHA3_ARM64|CRYPTO_AES_ARM64_CE_CCM|CRYPTO_SM[34]_ARM64_CE|SLAB_MERGE_DEFAULT|EROFS_FS_ZIP_LZMA|EROFS_FS_ZIP_DEFLATE|RCU_NOCB_CPU|NET_SCH_ETS|NET_SCH_PIE|SECURITY_LANDLOCK|SECTION_MISMATCH_WARN_ONLY|AUTOFDO_CLANG)=' $CFG
echo
echo "=== 4) olddefconfig ==="
make -s LLVM=1 ARCH=arm64 O=out olddefconfig 2>&1 | tail -3
grep -E '^CONFIG_(HZ|HZ_250|HZ_300|LLVM_POLLY|AUTOFDO_CLANG|LTO_CLANG_THIN|LTO_NONE)=' $CFG
} > "$OUT/log.txt" 2>&1

ACKN=138
NEXT=$(( $(cat out/.version 2>/dev/null || echo 45) + 1 ))
BV="${NEXT}-ack${ACKN}-p2"

{
echo
echo "=== 5) 构建  KBUILD_BUILD_VERSION=$BV ==="
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
echo "=== 6) 归档 + 双闸门 ==="
cp -f out/arch/arm64/boot/Image "$OUT/Image.p2"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.p2"
echo "  Image md5 = $(md5sum "$OUT/Image.p2" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.p2")   (opt15c = 36841984)"
echo "  横幅 = $(strings "$OUT/Image.p2" | grep -oE '[0-9]+-ack[0-9]+-p2 SMP PREEMPT[^"]{0,30}' | head -1)"
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
