#!/bin/bash
# 生成 opt6 的上游增量补丁: 只要"官方 09-14 的真实修复", 排除三类
#   A) 官方删绿厂特性/删我们在用项目的文件(BRUTAL、ssg 调度器、oplus_locking、rekernel)
#   B) 官方把私码换成 gitlink 的那几个路径(源码不在公仓, 拿不到)
#   C) .gitignore(只是忽略列表, 且含子模块路径)
set -e
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
OUT=/home/builder/opt6_upstream.patch
EX=(
  ':(exclude).gitignore'
  ':(exclude)net/ipv4/Kconfig' ':(exclude)net/ipv4/Makefile'
  ':(exclude)block/Kconfig.iosched' ':(exclude)block/Makefile' ':(exclude)block/elevator.c'
  ':(exclude)drivers/Kconfig' ':(exclude)drivers/Makefile'
  ':(exclude)kernel/locking/locking_main.h' ':(exclude)kernel/locking/sa_common_struct.h' ':(exclude)kernel/locking/oplus_locking.c'
  ':(exclude)kernel/oplus_cpu' ':(exclude)drivers/soc/oplus/oplus_resctrl' ':(exclude)drivers/soc/oplus/storage'
)
echo "=== 将要纳入的文件 ==="
git diff --diff-filter=d --numstat 7a244ff18 FETCH_HEAD -- . "${EX[@]}" | sort -k1,1rn
git diff --diff-filter=d 7a244ff18 FETCH_HEAD -- . "${EX[@]}" > "$OUT"
echo
echo "=== 补丁大小: $(wc -l < "$OUT") 行 / $(du -h "$OUT" | cut -f1) ==="
echo "=== 干跑能否对上当前树(--check) ==="
git apply --check --verbose "$OUT" 2>&1 | tail -20
