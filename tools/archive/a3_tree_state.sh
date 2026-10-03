#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$TREE" || exit 1
git config --global --add safe.directory "$TREE" 2>/dev/null
echo '=== 1) a3 构建时工作区到底改了哪些文件 ==='
git rev-parse --abbrev-ref HEAD
git status --porcelain | grep -E '^ M|^\?\?' | sed 's/^/  /'
echo
echo '=== 2) 白名单文件相对 HEAD 有没有被改 ==='
git diff --numstat -- android/abi_gki_aarch64_oplus | sed 's/^/  /'
echo "  (上面为空 = 没动过)"
echo
echo '=== 3) 那 6 个 hook 名字在白名单文件里本来就有吗 ==='
for h in android_vh_lock_task_fork android_vh_resched_curr_lazy android_vh_clear_curr_lazy; do
  printf '  %-34s 白名单命中=%s\n' "$h" "$(grep -c "$h" android/abi_gki_aarch64_oplus)"
done
echo
echo '=== 4) 这些 hook 在树里由哪个文件 EXPORT(DEFINE_HOOK/DECLARE_HOOK) ==='
git grep -ln 'android_vh_lock_task_fork' | sed 's/^/  /'
echo '--- vendor_hooks.c 里 DEFINE 它的条件 ---'
git grep -n 'android_vh_lock_task_fork\|android_vh_resched_curr_lazy' -- drivers/android/vendor_hooks.c include/trace/hooks 2>/dev/null | head -8 | sed 's/^/  /'
echo
echo '=== 5) TRIM_UNUSED_KSYMS 的真实判据: 白名单文件路径配置 ==='
grep -E 'CONFIG_TRIM_UNUSED_KSYMS|CONFIG_UNUSED_KSYMS_WHITELIST' /home/builder/opt5-baseline/config | sed 's/^/  /'
echo '--- 该白名单文件里 test_task_ux 在不在(opt5 有没有导出它) ---'
grep -c 'test_task_ux' /home/builder/opt5-baseline/Module.symvers
