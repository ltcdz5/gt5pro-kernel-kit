#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
git config --global --add safe.directory "$TREE" 2>/dev/null
echo "=== 树身份 ==="
git log --oneline -1
grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL' Makefile | tr -d '\t'

echo
echo '=== 1) hmbird/风驰 相关代码在不在树里 ==='
for k in hmbird es4g scx sched_ext ogki; do
  printf '  %-10s 文件名命中=%-4s  源码引用文件数=%s\n' "$k" \
    "$(git ls-files | grep -ic "$k")" \
    "$(git grep -il "$k" -- kernel init 2>/dev/null | wc -l)"
done
echo '--- sched_ext 相关文件 ---'
git ls-files | grep -iE 'sched/ext|scx' | sed 's/^/  /'
echo '--- 引用 ext.c 的 Kconfig 项 ---'
git grep -n 'SCHED_CLASS_EXT' -- kernel/sched/Kconfig init/Kconfig kernel/sched/Makefile 2>/dev/null | sed 's/^/  /'

echo
echo '=== 2) 现役 opt5 配置里 sched_ext 到底开没开 ==='
grep -E 'SCHED_CLASS_EXT|BPF_SYSCALL|NET_SCHEDULER?_?' "$BASE/config" | sed 's/^/  /'
echo '--- ext.c 有没有被编进去 (Makefile 条件) ---'
grep -n 'ext' kernel/sched/Makefile | sed 's/^/  /'
grep -n 'EXT' kernel/sched/build_policy.c 2>/dev/null | head -5 | sed 's/^/  /'

echo
echo '=== 3) 刷出来的内核里有没有 scx 的痕迹 ==='
for f in /home/builder/opt5-baseline/System.map; do
  echo "  $f: sched_ext 符号数=$(grep -c 'ext\|scx' $f 2>/dev/null), __scf/sched_ext_root 命中=$(grep -cE 'sched_ext_|scx_' $f)"
done
echo '  --- 现役 System.map 里找 sched_ext_class / ext_scheduler ---'
grep -E ' (sched_ext_class|ext_core_get|scx_pick_idle_cpu|register_ext_sched)' /home/builder/opt5-baseline/System.map | head -5
echo
echo '=== 4) cctv18 的补丁里有没有 scx 相关 ==='
ls /home/builder/kwork/cctv18/repo/local/*.patch* /home/builder/kwork/cctv18/repo/local/patches 2>/dev/null | head -20
grep -il 'scx\|sched_ext\|hmbird' /home/builder/kwork/cctv18/repo/local/*.patch* 2>/dev/null
