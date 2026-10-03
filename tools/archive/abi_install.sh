#!/bin/bash
# 装 ABI 布局对比工具 + 立刻在现有 vmlinux 上做可行性验证
set -x
which pahole abidiff 2>/dev/null
apt-cache policy dwarves libabigail-tools 2>/dev/null | grep -E '^[a-z]|Candidate'
export DEBIAN_FRONTEND=noninteractive
apt-get install -y dwarves libabigail-tools 2>&1 | tail -25
set +x
echo "=== 版本 ==="
pahole --version 2>&1 | head -2
abidiff --version 2>&1 | head -3
echo "=== 可行性: 从现有 vmlinux 读 task_struct ==="
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common
ls -l out/vmlinux
pahole -C task_struct out/vmlinux 2>&1 | head -20
