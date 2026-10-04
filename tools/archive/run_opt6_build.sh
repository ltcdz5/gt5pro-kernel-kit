#!/bin/bash
# opt6 编译: 与 opt5 同一套流程(AOSP clang 17 前置 PATH + ccache), 唯一区别是分支=opt6
cd /home/builder/kwork/cctv18/repo || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
echo "=== 分支确认(必须是 opt6) ==="
git -C "$TREE" rev-parse --abbrev-ref HEAD
git -C "$TREE" log -1 --format='%h %s' | cut -c1-90
echo "=== clang 确认(必须 AOSP 17.0.2) ==="
which clang; clang --version 2>&1 | head -1
echo "=== 起点 Image 时间戳(用于确认产物是本轮新出的) ==="
ls -la "$TREE/out/arch/arm64/boot/Image" 2>/dev/null || echo "  (无旧 Image)"
echo "=== 开始 $(date) ==="
bash local/builder_6.1.141.sh 2>&1 | tee /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/opt6_build.log
echo "=== 结束 $(date) ==="
ls -la "$TREE/out/arch/arm64/boot/Image"
