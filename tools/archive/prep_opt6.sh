#!/bin/bash
# opt6 准备: 保住 opt5 的基线产物与我们的改动, 然后切到官方 tip 建树
# 用法: bash prep_opt6.sh           (只做到"切好树+搬好改动", 不起编)
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
SAFE=/home/builder/kwork/opt5-baseline
cd "$TREE"

echo "=== 1) 先把 opt5 的基线产物与改动存盘到 $SAFE ==="
mkdir -p "$SAFE"
cp -f out/Module.symvers "$SAFE/Module.symvers.opt5" 2>/dev/null || echo "  ! 没有 out/Module.symvers"
cp -f out/.config          "$SAFE/config.opt5"        2>/dev/null || echo "  ! 没有 out/.config"
cp -f out/System.map       "$SAFE/System.map.opt5"    2>/dev/null || echo "  ! 没有 out/System.map"
git rev-parse HEAD > "$SAFE/opt5-head.txt"
git diff > "$SAFE/our-uncommitted.patch"          # gki_defconfig 追加块 + setlocalversion 后缀
cp -r firmware "$SAFE/firmware"                    # regdb 两个文件
echo "  已存: $(ls "$SAFE" | tr '\n' ' ')"

echo "=== 2) 把当前状态固化成分支 opt5-state (随时可 checkout 回来) ==="
git add -A >/dev/null 2>&1 || true
git -c user.name=ltcdz5 -c user.email=ltcdz5@users.noreply.github.com \
  commit -q -m "opt5 state: clean gki_defconfig block + regdb firmware + -ltcdz5 suffix" || echo "  (无新改动或已提交)"
git branch -f opt5-state HEAD
echo "  opt5-state = $(git rev-parse --short opt5-state)"

echo "=== 3) 以官方 tip 为基底开 opt6 分支 ==="
git checkout -q -B opt6 FETCH_HEAD
echo "  现在 HEAD = $(git log -1 --format='%h %cI %s' | cut -c1-110)"

echo "=== 4) 搬我们的改动过去 ==="
cp -r "$SAFE/firmware" . 2>/dev/null || true
git apply --verbose "$SAFE/our-uncommitted.patch" 2>&1 | tail -5 || echo "  ! patch 没直接对上, 需手工搬 my_opts 块"
echo "  setlocalversion 最后一行: $(tail -1 scripts/setlocalversion)"
echo "  gki_defconfig 行数: $(wc -l < arch/arm64/configs/gki_defconfig)"
echo "  regdb 文件: $(ls -la firmware/ 2>/dev/null | grep -c regulatory)"
echo "=== 完成 ==="
