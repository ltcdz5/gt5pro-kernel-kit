#!/bin/bash
# opt15b: 退掉 29 条会改 CRC 的补丁, 保留 142 条, 并把版本后缀改成 opt15
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/USERNAME/AppData/Local/Temp/ack_patches2
OUT=/home/builder/opt15
KEEP=$OUT/crc_keep.txt
LOG=$OUT/build15b.log

mkdir -p "$OUT"
cd "$K" || exit 1

{
echo "=== 复位 ==="
git checkout -- .
echo "  改动数: $(git status --porcelain | wc -l)  HEAD: $(git rev-parse --short HEAD)"
echo
echo "=== 版本后缀 ==="
grep -n 'opt1' scripts/setlocalversion || echo "  (setlocalversion 里没找到 opt1x)"
sed -i 's/-opt14/-opt15/g; s/opt14/opt15/g' scripts/setlocalversion
grep -n 'opt1' scripts/setlocalversion || true
echo
echo "=== 应用保留的 $(wc -l < "$KEEP") 条 ==="
: > "$OUT/apply15b.log"
n_ok=0; n_fail=0
while read -r sha; do
  [ -z "$sha" ] && continue
  if git apply "$P/$sha.patch" 2>>"$OUT/apply15b.err"; then
    printf 'OK\t%s\n' "$sha" >> "$OUT/apply15b.log"; n_ok=$((n_ok+1))
  else
    printf 'FAIL\t%s\n' "$sha" >> "$OUT/apply15b.log"; n_fail=$((n_fail+1))
  fi
done < "$KEEP"
echo "  成功=$n_ok 失败=$n_fail"
grep -P '^FAIL' "$OUT/apply15b.log" || true
echo
echo "=== 改动规模 ==="
git status --porcelain | wc -l
git diff --stat | tail -1
echo
echo "=== 构建 ==="
} > "$LOG" 2>&1

make -k -j"$(nproc)" LLVM=1 ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- \
  'CC=ccache clang' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out \
  KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image > "$OUT/build15b_make.log" 2>&1
rc=$?
{
echo "  make rc=$rc  错误行=$(grep -cE 'error:' "$OUT/build15b_make.log" || true)"
} >> "$LOG" 2>&1

if [ "$rc" -ne 0 ]; then
  {
  echo "  --- 错误 (去 tcp.h 级联) ---"
  grep -E 'error:' "$OUT/build15b_make.log" | grep -vE 'include/linux/tcp\.h|include/net/tcp\.h|too many errors' | head -30
  } >> "$LOG" 2>&1
  exit 1
fi

{
echo
echo "=== 归档 ==="
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt15b_full"
cp -f out/System.map "$OUT/System.map.opt15b_full"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt15b"
echo "  Image md5  = $(md5sum "$OUT/Image.opt15b_full" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.opt15b_full")"
echo "  版本串     = $(strings "$OUT/Image.opt15b_full" | grep -m1 'Linux version' | cut -c1-70)"
echo
echo "=== 闸门 1: 导出集合 ==="
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py out/vmlinux.symvers
echo "  导出闸门 rc=$?"
echo
echo "=== 闸门 2: 厂商 CRC 真值 ==="
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_vko_crc.py out/vmlinux.symvers \
  /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm \
  /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/system_dlkm
echo "  CRC 闸门 rc=$?"
echo "=== 完成 ==="
} >> "$LOG" 2>&1
