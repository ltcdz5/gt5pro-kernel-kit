#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE"
echo "=== 当前分支/工作区 ==="
git rev-parse --abbrev-ref HEAD; git rev-parse --short HEAD
git status --porcelain | head -5
echo "=== 现有 out/ 里有什么 ==="
ls -l out/vmlinux out/System.map out/Module.symvers out/.config 2>&1
echo "=== opt5 基线存档 ==="
ls -l "$BASE"
echo "=== 各分支 ==="
git branch -v | sed 's/^/  /'
echo "=== 磁盘 ==="
df -h /home/builder | tail -1
echo "=== ccache ==="
ccache -s 2>/dev/null | head -4
