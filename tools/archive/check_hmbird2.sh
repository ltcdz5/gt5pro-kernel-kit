#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
git config --global --add safe.directory "$TREE" 2>/dev/null

echo '=== A) hmbird 到底是哪些文件 ==='
git ls-files | grep -i hmbird | sed 's/^/  /'
echo '--- 引用 hmbird 的文件 ---'
git grep -il hmbird | sed 's/^/  /'

echo
echo '=== B) hmbird 的开关 + 现役配置里的值 ==='
git grep -n 'config HMBIRD\|HMBIRD' -- '*Kconfig*' | head -10 | sed 's/^/  /'
echo '--- 现役 opt5 config 里的 HMBIRD/EXT 项 ---'
grep -iE 'HMBIRD|SCHED_CLASS_EXT|CGROUP_SCHED' "$BASE/config" | sed 's/^/  /'

echo
echo '=== C) 刷进手机的那个内核(System.map)里有没有 hmbird 符号 ==='
echo "  System.map 含 hmbird 行数=$(grep -ic hmbird $BASE/System.map)"
grep -i hmbird $BASE/System.map | head -8 | sed 's/^/    /'

echo
echo '=== D) /sys/kernel/sched_ext 是谁建的、什么条件下建(解释手机上为何看不到) ==='
grep -n 'sched_ext\b.*kset\|kobject_create_and_add\|sys_kset\|kernel_kobj' kernel/sched/ext.c | head -12 | sed 's/^/  /'
grep -n 'static int __init sched_ext_offline_cpumask_init\|root_kset\|sched_ext_init' kernel/sched/ext.c | head -10 | sed 's/^/  /'
echo '--- 建 sysfs 那段代码的上下文 ---'
awk '/kobject_create_and_add/{print NR": "$0}' kernel/sched/ext.c | head -3
