#!/bin/bash
# 核实贴来的材料里那几个可执行点, 在本地树上直接查
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$TREE" || exit 1
echo "=== 树身份 ==="
git log --oneline -1
grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL|^EXTRAVERSION' Makefile | tr -d '\t'

echo
echo '=== 1) 风驰/hmbird 调度类在不在这棵树里 ==='
for k in hmbird es4g scx sched_ext ogki OGKI; do
  printf '  %-10s 文件名命中=%-4s 代码命中=%s\n' "$k" \
    "$(git ls-files | grep -ic "$k")" \
    "$(git grep -il "$k" -- kernel/sched init/Kconfig kernel/Makefile 2>/dev/null | wc -l)"
done

echo
echo '=== 2) 这棵树的版本串是怎么拼出来的(=所谓"改版本号"的全部机制) ==='
grep -n 'LOCALVERSION\|EXTRAVERSION' Makefile | head -6
echo '--- setlocalversion 末行(我们的后缀在这) ---'
tail -3 scripts/setlocalversion
echo '--- 当前分支算出来的完整 uname -r ---'
make ARCH=arm64 kernelversion 2>/dev/null
printf '  实际 = %s%s\n' "$(make ARCH=arm64 kernelversion 2>/dev/null)" "$(sed -n 's/^echo "\(.*\)"$/\1/p' scripts/setlocalversion | tail -1)"

echo
echo '=== 3) 原厂配置里 sched_ext 的可能性: 6.1 有没有这个特性 ==='
ls kernel/sched/ext* 2>/dev/null || echo '  无 kernel/sched/ext.c —— 6.1 树根本没有 sched_ext'
grep -c SCHED_CLASS_GROUPS kernel/sched/Makefile 2>/dev/null
echo '--- 本树有的自定义调度类 ---'
git grep -l 'sched_class' -- kernel/sched | head
ls kernel/sched/*.c | sed 's/^/  /'
