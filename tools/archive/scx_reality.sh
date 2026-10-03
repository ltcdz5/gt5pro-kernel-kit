#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE"; git config --global --add safe.directory "$TREE" 2>/dev/null

echo '=== 1) sched_ext 暴露状态的确切路径(我上次查的是 /sys/kernel/sched_ext) ==='
grep -n 'debugfs_sched\|debugfs_create_file("ext"' kernel/sched/ext.c | head -6 | sed 's/^/  /'
grep -rn 'debugfs_sched =' kernel/sched/debug.c | sed 's/^/  /'
echo '  => 手机侧正确探针: /sys/kernel/debug/sched/ext'

echo
echo '=== 2) 走这条路需要的配置项, 在现役 opt5 里逐条查 ==='
for k in CONFIG_SCHED_CLASS_EXT CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_DEBUG_INFO_BTF \
         CONFIG_DEBUG_FS CONFIG_CGROUPS CONFIG_SCHED_DEBUG CONFIG_DEBUG_INFO CONFIG_FTRACE; do
  printf '  %-28s %s\n' "$k" "$(grep -m1 "^$k=" $BASE/config || echo MISSING)"
done

echo
echo '=== 3) 树里带的示例调度器(能不能本地编) ==='
ls tools/sched_ext/ 2>/dev/null | sed 's/^/  /' | head -14
echo '--- 它们要求的构建依赖 ---'
grep -nE 'libelf|bpftool|clang.*bpf|BPF_TARGET' tools/sched_ext/Makefile 2>/dev/null | head -8 | sed 's/^/  /'

echo
echo '=== 4) 现役内核里 scx 符号到底进镜像没有(在 opt5 的 BTF/类型里) ==='
pahole /home/builder/abi/btf/opt5-ltcdz5-raw.btf 2>/dev/null | grep -cE 'scx|sched_ext'
echo "  System.map 里 scx_/ext 符号数=$(grep -cE ' (t|T|d|D|b|B) .*(__sc|scx_|ext_update_all|sched_ext)' $BASE/System.map)"
grep -E ' (t|T) .*(scx_|sched_ext_|ext_mutex)' $BASE/System.map | head -10 | sed 's/^/  /'
