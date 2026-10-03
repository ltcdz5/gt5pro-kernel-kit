#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo '=== 1) 它注册的电梯名(echo 进 queue/scheduler 用的词) ==='
grep -n -A3 'static struct elevator_type' block/ssg-iosched.c | head -12 | sed 's/^/  /'
grep -n '\.name' block/ssg-iosched.c | head -6 | sed 's/^/  /'
echo
echo '=== 2) 它的调度策略要点(自己代码里的注释, 不是我转述) ==='
grep -nE '^ \* |^/\*' block/ssg-iosched.c | head -24 | sed 's/^/  /'
echo
echo '=== 3) 做成 .ko 的可行性: 它调用的内核函数在 opt5 里是否导出 ==='
LS=/home/builder/opt5-baseline/Module.symvers
# 取 ssg-iosched.c 里出现的函数调用名(粗取), 逐个查是否在导出表
for s in elv_rb_latter_request elv_rb_former_request elv_dispatch_add_sector elv_rb_add \
         blk_mq_start_request blk_mq_end_request blk_get_request blk_execute_rq \
         blk_mq_run_hw_queue blk_mq_requeue_request blk_mq_delay_run_hw_queue; do
  if grep -q "	$s	" "$LS"; then st=导出; else st='未导出'; fi
  used=$(grep -c "$s" block/ssg-iosched.c)
  printf '  %-32s 代码里用=%-4s 内核侧=%s\n' "$s" "$used" "$st"
done
echo
echo '=== 4) blk-sec.h 是什么(有没有 .c 说明是纯头还是缺件) ==='
wc -l block/blk-sec.h; head -22 block/blk-sec.h | sed 's/^/  /'
echo '--- 它声明的函数被 ssg 用到了吗(用到但无实现=链不上) ---'
for f in $(grep -oE '\b(blk_sec[a-z_]*)\(' block/blk-sec.h | tr -d '(' | sort -u | head -8); do
  printf '  %-24s ssg 里出现=%s\n' "$f" "$(grep -c "$f" block/ssg-iosched.c)"
done
