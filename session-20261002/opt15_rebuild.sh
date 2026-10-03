#!/bin/bash
# opt15 重建: 退掉 5 条缺前置的补丁, 重打 166 条并构建
set -u
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH

K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/USERNAME/AppData/Local/Temp/ack_patches2
OUT=/home/builder/opt15
LIST=/home/builder/opt14/ack2/apply_list.txt
EXCL=/home/builder/opt14/ack2/exclude_list.txt
LOG="$OUT/rebuild.log"

mkdir -p "$OUT"
cd "$K" || exit 1

# 5 条缺前置, 退掉
cat > "$EXCL" <<'EOF'
b3fd3e1e0c35
cfa745830e45
1d736ad183ed
acf62af18c7b
4f7d25f3f078
EOF

{
echo "=== 复位到 opt14 精简版基线 ==="
git checkout -- .
echo "  工作区改动数: $(git status --porcelain | wc -l)"
echo "  HEAD: $(git rev-parse --short HEAD)"
echo
echo "=== 待应用 = 171 - 5 = ? ==="
grep -vxF -f "$EXCL" "$LIST" > "$OUT/apply_list_166.txt"
wc -l < "$OUT/apply_list_166.txt"
echo
echo "=== 应用 ==="
: > "$OUT/apply2.log"
n_ok=0; n_fail=0
while read -r sha; do
  [ -z "$sha" ] && continue
  f="$P/$sha.patch"
  if git apply "$f" 2>>"$OUT/apply2.err"; then
    printf 'OK\t%s\n' "$sha" >> "$OUT/apply2.log"; n_ok=$((n_ok+1))
  else
    printf 'FAIL\t%s\n' "$sha" >> "$OUT/apply2.log"; n_fail=$((n_fail+1))
  fi
done < "$OUT/apply_list_166.txt"
echo "  成功=$n_ok 失败=$n_fail"
grep -P '^FAIL' "$OUT/apply2.log" || true
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
  KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image > "$OUT/build2.log" 2>&1
rc=$?
{
echo "  make rc=$rc"
echo "  错误行=$(grep -cE 'error:' "$OUT/build2.log" || true)"
} >> "$LOG" 2>&1

if [ "$rc" -ne 0 ]; then
  {
  echo "  --- 真实错误 (去 tcp.h 级联), 前 40 条 ---"
  grep -E 'error:' "$OUT/build2.log" | grep -vE 'include/linux/tcp\.h|include/net/tcp\.h|too many errors' | head -40
  } >> "$LOG" 2>&1
  exit 1
fi

{
echo "=== 归档 ==="
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt15_full"
cp -f out/System.map "$OUT/System.map.opt15_full"
echo "  Image md5  = $(md5sum "$OUT/Image.opt15_full" | cut -d' ' -f1)"
echo "  Image 大小 = $(stat -c %s "$OUT/Image.opt15_full")"
echo "=== 完成 ==="
} >> "$LOG" 2>&1
