#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo '=== 1) 电梯注册名的字符串(echo 进 queue/scheduler 就填这个) ==='
sed -n '845,885p' block/ssg-iosched.c | grep -nE '\.name|\.features|elevator_owner' | sed 's/^/  /'
grep -n 'MODULE_DESCRIPTION\|MODULE_AUTHOR' block/ssg-iosched.c | sed 's/^/  /'
echo
echo '=== 2) 有没有"设为默认电梯"的 Kconfig 项(别人帖里的"支持"通常是这个) ==='
grep -nE 'MQ_DEFAULT|DEFAULT_IOSCHED' block/Kconfig block/Kconfig.iosched | sed 's/^/  /'
echo "  本树 MQ_DEFAULT_* 命中数=$(grep -cE 'MQ_DEFAULT' block/Kconfig.iosched)"
echo '  内核实际默认电梯由谁定: CONFIG_DEFAULT_IOSCHED'
grep -n 'CONFIG_DEFAULT_IOSCHED\|ELEVATOR_DEFAULT' init/Kconfig block/Makefile 2>/dev/null | head -3 | sed 's/^/  /'
grep -E 'CONFIG_DEFAULT_IOSCHED' /home/builder/opt5-baseline/config | sed 's/^/  opt5: /'
echo
echo '=== 3) ssg 用到 blk-sec 的东西吗(没 .c, 若直接调用就链不上) ==='
grep -nE 'blk_sec|WB_REQ_|CONFIG_BLK_SEC' block/ssg-iosched.c block/ssg-stat.c block/ssg.h 2>/dev/null | head -10 | sed 's/^/  /'
echo "  BLK_SEC_COMMON 在 opt5 里: $(grep -E 'CONFIG_BLK_SEC_COMMON' /home/builder/opt5-baseline/config || echo '没有这项')"
echo
echo '=== 4) 它和 mq-deadline 的关系: 看它的 ops 数量与 deadline 对比(结构同源) ==='
for f in block/ssg-iosched.c block/mq-deadline.c; do
  printf '  %-24s 行数=%-6s fifo_list=%s rb_root=%s aging=%s\n' "$(basename $f)" "$(wc -l < $f)" \
    "$(grep -c fifo_list $f)" "$(grep -c rb_root $f)" "$(grep -ciE 'aging|batch' $f)"
done
echo '--- SSG 相对 deadline 多的东西(cgroup/stat 之外的独有机制) ---'
grep -nE 'ssg_stat|NR_WB_REQ|latency|prio_|batch_expire' block/ssg-iosched.c | head -10 | sed 's/^/  /'
