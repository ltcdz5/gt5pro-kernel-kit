#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo "=== 磁盘剩余 ==="
df -h /home/builder | tail -1
echo "=== 树大小 / .git 大小 ==="
du -sh . 2>/dev/null | tail -1
du -sh .git 2>/dev/null | tail -1
echo "=== remotes ==="
git remote -v
echo "=== 最近 3 条提交 ==="
git log --oneline -3
echo "=== 基线 7a244ff18 在不在本地 ==="
git cat-file -t 7a244ff18 2>&1 | head -1
echo "=== 是否 shallow 克隆 ==="
[ -f .git/shallow ] && echo "shallow ($(wc -l < .git/shallow) 个边界)" || echo "full"
echo "=== 工作区未提交改动(前 12 行) ==="
git status --porcelain | head -12
echo "=== firmware/ 内嵌文件在不在 ==="
ls -la firmware/ 2>/dev/null | grep -i regulatory || echo "树根没有 firmware/regulatory.db"
echo "=== setlocalversion 后缀 ==="
tail -3 scripts/setlocalversion
