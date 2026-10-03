#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common
export PATH=/home/builder/kwork/toolchains/llvm-r49c07-prebuilt_aarch64-clang/bin:$PATH
which llvm-objcopy objcopy
llvm-objcopy --dump-section .BTF=/tmp/base.btf out/vmlinux 2>&1 | head -3
ls -l /tmp/base.btf
echo "=== pahole 读裸 BTF (-F btf) ==="
pahole -F btf -C task_struct /tmp/base.btf 2>&1 | head -8
echo "=== pahole 读裸 BTF 全量 struct 计数 ==="
pahole -F btf /tmp/base.btf 2>&1 | grep -c '^struct '
echo "=== 对照: 读 ELF vmlinux 全量 struct 计数 ==="
pahole out/vmlinux 2>/dev/null | grep -c '^struct '
