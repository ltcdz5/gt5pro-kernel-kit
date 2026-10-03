#!/bin/bash
# 建 opt6 分支: 先把 opt5 现场固化+存基线产物, 再打上游增量, 换版本后缀
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE"

echo "=== 1) 存 opt5 基线产物到 $BASE ==="
mkdir -p "$BASE"
cp -f out/Module.symvers   "$BASE/Module.symvers" 2>/dev/null || echo "  ! 无 out/Module.symvers"
cp -f out/.config          "$BASE/config"         2>/dev/null || echo "  ! 无 out/.config"
cp -f out/System.map       "$BASE/System.map"     2>/dev/null || echo "  ! 无 out/System.map"
cp -f out/arch/arm64/boot/Image "$BASE/Image.opt5" 2>/dev/null || echo "  ! 无 Image"
ls -la "$BASE" | tail -5

echo "=== 2) 固化 opt5 现场(建分支 opt5-state) ==="
git add -f arch/arm64/configs/gki_defconfig scripts/setlocalversion firmware/regulatory.db firmware/regulatory.db.p7s 2>/dev/null
git -c user.name=ltcdz5 -c user.email=ltcdz5@users.noreply.github.com commit -q -m "opt5 state: regdb 内嵌 + 799 行干净 defconfig + -ltcdz5 后缀" || echo "  (无待提交改动)"
git branch -f opt5-state HEAD
echo "  opt5-state = $(git rev-parse --short HEAD)  Image 指纹: $(md5sum "$BASE/Image.opt5" 2>/dev/null | cut -c1-12)"

echo "=== 3) 开 opt6 并打上上游增量 ==="
git checkout -q -B opt6
git apply --stat /home/builder/opt6_upstream.patch | tail -3
git apply /home/builder/opt6_upstream.patch
echo "  打补丁后改动文件数: $(git status --porcelain | wc -l)"

echo "=== 4) 换版本后缀(让他能在设置里认出是哪版) ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-up0914"/' scripts/setlocalversion
tail -1 scripts/setlocalversion

git add -A
git -c user.name=ltcdz5 -c user.email=ltcdz5@users.noreply.github.com commit -q -m "opt6: 同步 OnePlusOSS b_16.0.0_oneplus12 @2026-09-14 上游增量(25 文件, 只取修复不取删除/不取 gitlink)"
echo "  opt6 = $(git rev-parse --short HEAD)"
echo "=== 完成 ==="
