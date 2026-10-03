#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo '=== 1) SSG 依赖的文件在不在 ==='
for f in block/blk-sec.h block/blk-sec.c block/elevator.h block/elevator.c \
         block/blk-mq-tag.h block/blk-mq-sched.h block/ssg.h block/ssg-stat.c \
         block/blk-mq-debugfs.h; do
  if [ -e "$f" ]; then echo "  有  $f"; else echo "  缺  $f"; fi
done
echo
echo '=== 2) ssg-iosched.c 里 include 的本地头全都在吗(缺一个就编不过) ==='
grep -n '^#include "' block/ssg-iosched.c | sed 's/^/  /'
for h in $(grep -o '"[a-z0-9.-]*\.h"' block/ssg-iosched.c | tr -d '"'); do
  if [ -e "block/$h" ]; then echo "  有  block/$h"; else echo "  缺  block/$h"; fi
done
echo
echo '=== 3) 它注册成的电梯名(echo 进 /sys/block/*/queue/scheduler 用的词) ==='
grep -n -B2 -A8 'elevator_type' block/ssg-iosched.c | grep -E '\.|name' | head -12 | sed 's/^/  /'
echo
echo '=== 4) 它是不是会碰别的电梯的默认值(MQ_DEFAULT 选项) ==='
grep -nE 'MQ_DEFAULT|IOSCHED_SSG' block/Kconfig.iosched | sed 's/^/  /'
echo
echo '=== 5) ssg.h 里对外部符号的依赖(blk_sec 之类) ==='
grep -nE 'blk_sec|ssg_|extern' block/ssg.h | head -20 | sed 's/^/  /'
