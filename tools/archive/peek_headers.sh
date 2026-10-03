#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
for f in include/linux/mm_types.h include/linux/blk-mq.h include/linux/file.h include/trace/hooks/dtask.h; do
  echo "############ $f ############"
  git diff 7a244ff18 FETCH_HEAD -- "$f" | sed -n '1,80p'
done
