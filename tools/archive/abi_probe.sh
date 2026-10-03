#!/bin/bash
# 1) 补装 abidiff  2) 从现有 vmlinux 抽出 .BTF  3) 验证 dwarves 能否直接吃裸 BTF 文件
export DEBIAN_FRONTEND=noninteractive
apt-get install -y abigail-tools >/tmp/abidiff_install.log 2>&1
echo "abidiff: $(abidiff --version 2>&1 | head -1)"

cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common
readelf -S out/vmlinux | grep -E '\.BTF' || echo "没有 .BTF 段"
objcopy --dump-section .BTF=/tmp/base.btf out/vmlinux && ls -l /tmp/base.btf

echo "=== btfdump 能否读裸 BTF ==="
which btfdump
btfdump /tmp/base.btf 2>&1 | head -8
echo "=== pahole 能否读裸 BTF（-F btf） ==="
pahole -F btf -C task_struct /tmp/base.btf 2>&1 | head -12
echo "=== pahole 读 ELF vmlinux 里的 struct size 行样例 ==="
pahole out/vmlinux 2>/dev/null | grep -c '^struct '
