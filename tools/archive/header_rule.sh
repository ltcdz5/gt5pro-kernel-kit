#!/bin/bash
T=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$TREE" 2>/dev/null
echo '=== A) -a 那一轮的文件清单(和 -a2 差什么) ==='
grep -n 'A=(\|^A2=(\|A=(' "$T/build_opt6a.sh" 2>/dev/null | tr -d '\r' | head -4
grep -n 'include/' "$T/build_opt6a.sh" 2>/dev/null | tr -d '\r' | head -4

echo
echo '=== B) 我们自己的 opt5 相对 snap-6.1.141 上游基线改了哪些 .h (规则会不会被自己否证) ==='
git config --global --add safe.directory "$TREE" 2>/dev/null
git diff --name-only snap-6.1.141 opt5-state 2>/dev/null | grep -E '\.h$' | sed 's/^/  /'
echo "  opt5 改动的头文件总数=$(git diff --name-only snap-6.1.141 opt5-state 2>/dev/null | grep -cE '\.h$')"
echo "  其中 include/linux/ 下=$(git diff --name-only snap-6.1.141 opt5-state 2>/dev/null | grep -cE '^include/linux/.*\.h$')"
echo
echo '=== C) opt5 改动的全部文件里 include/ 目录占比 ==='
git diff --name-only snap-6.1.141 opt5-state 2>/dev/null | grep -E '^include/' | sed 's/^/  /' | head -20

echo
echo '=== D) 厂商 .ko 有没有在本地留档(能做 import 闭集闸吗) ==='
ls -d /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/*ko* /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/**/*.ko 2>/dev/null | head -5
find /home/builder -maxdepth 3 -name '*.ko' 2>/dev/null | head -5
find /mnt/c/Users/xutengfa/Desktop -maxdepth 3 -name '*.ko' 2>/dev/null | head -8
echo "  本地 .ko 计数=$(find /home/builder /mnt/c/Users/xutengfa/Desktop -name '*.ko' 2>/dev/null | wc -l)"
