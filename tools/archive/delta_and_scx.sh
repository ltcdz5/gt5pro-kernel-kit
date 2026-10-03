#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$TREE" || exit 1
git config --global --add safe.directory "$TREE" 2>/dev/null

echo '=== 1) 各分支真实存在吗 ==='
git branch -a --format='%(refname:short) %(objectname:short)' | sed 's/^/  /'

echo
echo '=== 2) -a2 相对 opt5-state 改了哪些文件(砖掉的最小版) ==='
git diff --stat opt5-state opt6a2 2>/dev/null | sed 's/^/  /' || echo '  opt6a2 分支不存在'

echo
echo '=== 3) -a 相对 opt5-state ==='
git diff --stat opt5-state opt6a 2>/dev/null | tail -3 | sed 's/^/  /'
echo '=== 4) opt6 相对 opt5-state ==='
git diff --stat opt5-state opt6 2>/dev/null | tail -3 | sed 's/^/  /'

echo
echo '=== 5) scx 在这棵 6.1 回移版里到底暴露了什么接口(手机侧正确判据) ==='
grep -n 'debugfs\|DEFINE_SHOW_ATTRIBUTE\|seq_file' kernel/sched/ext.c | head -8 | sed 's/^/  /'
grep -n 'ext' kernel/sched/debug.c | grep -i 'sched_ext\|debugfs_create' | head -6 | sed 's/^/  /'
echo '--- 有没有 sys/kernel/sched_ext 的创建代码 ---'
grep -rn 'sched_ext"' kernel/sched/*.c | head -5 | sed 's/^/  /'
echo '--- 注册调度器走哪个 syscall 结构体(bpf_struct_ops) ---'
grep -n 'BPF_MAP_TYPE_struct_ops\|register_struct_ops\|bpf_struct_ops' kernel/sched/ext.c | head -4 | sed 's/^/  /'
