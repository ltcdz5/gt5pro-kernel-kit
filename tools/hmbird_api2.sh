#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/hmbird_api2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git config --global --add safe.directory "$PWD" 2>/dev/null

echo '=== 0) fetch 现场: 有没有在下东西 / 有没有残留进程 ==='
ls -l .git/objects/pack/ 2>/dev/null | tail -4 | sed 's/^/  /'
ls .git/objects/pack/tmp_pack_* 2>/dev/null | sed 's/^/  临时包: /' || echo '  无临时包(说明握手就没成)'
pgrep -a git | head -3 | sed 's/^/  残留: /' || echo '  无 git 进程'

echo
echo '=== 1) 我们的 task_struct 里 scx 是内嵌还是指针 ==='
grep -n 'sched_ext_entity' include/linux/sched.h | sed 's/^/  /'
grep -n 'struct sched_ext_entity {' include/linux/sched/topology.h include/linux/sched/ext.h 2>/dev/null | sed 's/^/  /'

echo
echo '=== 2) hmbird main.c 实际用的访问形式 ==='
echo "  p->scx-> 形式出现次数: $(grep -c 'p->scx->' kernel/oplus_cpu/sched_ext/main.c)"
echo "  p->scx.  形式出现次数: $(grep -c 'p->scx\.' kernel/oplus_cpu/sched_ext/main.c)"
grep -oE 'p->scx(->|\.)[a-z_]+' kernel/oplus_cpu/sched_ext/main.c | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'

echo
echo '=== 3) 原厂调试串里的内部名, 在我们树里有没有(有=同代) ==='
for name in task_linked_on_dsq SCX_TASK_OPS_PREPPED SCX_TASK_DSQ_ON_PRIQ scx_consume_dsq_allowed scx_deadline_idx scx_cpu_exclusive scx_get_md_info scx_update_task_scale_time scx_fatal_info; do
  hits=$(grep -rl -- "$name" kernel/sched include/linux/sched include/linux 2>/dev/null | wc -l)
  hmb=$(grep -rl -- "$name" kernel/oplus_cpu 2>/dev/null | wc -l)
  printf '  %-28s 我们内核树=%s  oplus_cpu=%s\n' "$name" "$hits" "$hmb"
done

echo
echo '=== 4) oplus_cpu/sched_ext 怎么被 Kconfig 接进来的 ==='
echo '  --- init/Kconfig:877 附近 ---'
sed -n '870,885p' init/Kconfig | sed 's/^/    /'
echo '  --- kernel/oplus_cpu/sched/Kconfig 里与 ext/assist 有关的项 ---'
grep -rn -A4 'config OPLUS_FEATURE_SCHED_ASSIST' kernel/oplus_cpu/sched/Kconfig 2>/dev/null | head -14 | sed 's/^/    /'
echo '  --- sched_ext 目录有没有 Makefile/Kconfig(有=可内建) ---'
ls kernel/oplus_cpu/sched_ext/ | sed 's/^/    /'

echo
echo '=== 5) 原厂串里那个 <hmbird_sched> 是 ops 注册名: 我们树里搜同名 ==='
grep -rn 'hmbird_sched' kernel/oplus_cpu | head -8 | sed 's/^/  /'
echo "  .name 形式: $(grep -rn '\.name *= *"hmbird' kernel/oplus_cpu | wc -l) 处"
