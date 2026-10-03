#!/bin/bash
# 性能实验 P1: 开 ThinLTO (Google GKI 6.1 的配置), 并把 ACK 条数写进横幅
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
OUT=/home/builder/perf1
mkdir -p "$OUT"
cd "$K" || exit 1

{
echo "=== 0) 起点 ==="
echo "  HEAD: $(git rev-parse --short HEAD)  ($(git log -1 --format=%s | cut -c1-60))"
echo "  工作区改动: $(git status --porcelain | wc -l)"
echo
echo "=== 1) 备份 config ==="
cp -f out/.config "$OUT/.config.before"
echo "  已备份到 $OUT/.config.before"
echo
echo "=== 2) LTO 相关 Kconfig 是否可用 ==="
grep -n -A6 '^config LTO_CLANG_THIN' arch/Kconfig 2>/dev/null | head -12
echo "  --- 当前 ---"
grep -E '^CONFIG_(LTO|LTO_CLANG|LTO_CLANG_THIN|LTO_CLANG_FULL|LTO_NONE|CFI_CLANG|LD_IS_LLD)=' out/.config
echo
echo "=== 3) 开 ThinLTO ==="
./scripts/config --file out/.config -e LTO_CLANG -e LTO_CLANG_THIN -d LTO_NONE
grep -E '^CONFIG_(LTO|LTO_CLANG|LTO_CLANG_THIN|LTO_CLANG_FULL|LTO_NONE|CFI_CLANG)=' out/.config
echo
echo "=== 4) olddefconfig 解析依赖 ==="
make -s LLVM=1 ARCH=arm64 O=out olddefconfig 2>&1 | tail -5
grep -E '^CONFIG_(LTO|LTO_CLANG|LTO_CLANG_THIN|LTO_NONE|CFI_CLANG)=' out/.config
echo
echo "=== 5) 横幅: ACK 条数写进 UTS_VERSION ==="
ACKN=$(wc -l < "$OUT/../opt15/crc_keep_final.txt")
NEXT=$(( $(cat out/.version 2>/dev/null || echo 44) + 1 ))
echo "  ACK 条数 = $ACKN   下一次构建号 = $NEXT"
echo "  KBUILD_BUILD_VERSION = #$NEXT-ack$ACKN"
echo
echo "=== 5b) 守卫: LTO 真的开了吗 ==="
if grep -q '^CONFIG_LTO_CLANG_THIN=y' out/.config; then
  echo "  ✅ CONFIG_LTO_CLANG_THIN=y"
else
  echo "  ★ LTO 没开成 —— olddefconfig 把依赖解掉了。中止, 不浪费构建时间。"
  echo "  当前: $(grep -E '^CONFIG_LTO' out/.config | tr '\n' ' ')"
  exit 3
fi
} > "$OUT/log.txt" 2>&1

ACKN=$(wc -l < /home/builder/opt15/crc_keep_final.txt)
NEXT=$(( $(cat out/.version 2>/dev/null || echo 44) + 1 ))
BV="#${NEXT}-ack${ACKN}"

{
echo
echo "=== 6) 构建 (ThinLTO + 横幅) ==="
echo "  KBUILD_BUILD_VERSION=$BV"
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
  {
  echo "  --- 错误前 30 条 ---"
  grep -E 'error:|undefined symbol|ld.lld: error' "$OUT/make.log" | head -30
  } >> "$OUT/log.txt" 2>&1
  exit 1
fi

{
echo
echo "=== 7) 归档 + 双闸门 ==="
cp -f out/arch/arm64/boot/Image "$OUT/Image.perf1"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.perf1"
echo "  Image md5 = $(md5sum "$OUT/Image.perf1" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.perf1")   (opt15c 是 36841984)"
echo "  横幅 = $(strings "$OUT/Image.perf1" | grep -m1 'Linux version' | cut -c1-90)"
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
