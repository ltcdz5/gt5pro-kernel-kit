#!/bin/bash
set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

for B in opt45 opt46; do
  echo "########## 构建 $B 并提取 ABI 语料 ##########"
  git checkout -q $B || { echo "切不到 $B"; continue; }
  echo "  HEAD=$(git log --oneline -1)"
  eval make -j"$(nproc)" $MFLAGS KBUILD_BUILD_VERSION="abi-$B" Image > /tmp/abi-$B.log 2>&1
  echo "  make rc=$?"
  [ -f out/vmlinux ] || { echo "  没有 vmlinux"; continue; }
  time abidw --no-corpus-path --no-show-locs out/vmlinux > /home/builder/abi-$B.xml 2>/tmp/abidw-$B.err
  echo "  abidw rc=$?  大小=$(stat -c%s /home/builder/abi-$B.xml 2>/dev/null)"
done
echo
echo "########## 恢复 opt47 分支与产物 ##########"
git checkout -q opt47
eval make -j"$(nproc)" $MFLAGS KBUILD_BUILD_VERSION="74-ack304-v1.1-opt47" Image > /tmp/abi-restore.log 2>&1
echo "  make rc=$?"
strings -a out/arch/arm64/boot/Image | grep -m1 -oE "#[0-9]+-ack304-v1.1-opt[0-9]+"
echo "完成 $(date)"
