#!/bin/bash
K=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel
B=/home/builder/opt5-baseline
V=$K/kernel-kit/verify_image.sh
for pair in "opt6(砖)|$B/Image.opt6" \
            "-a-A组(砖)|$K/images/不能刷-裸内核/boot-opt6a-upstream.raw.img" \
            "-a2-去f2fs(砖)|$K/images/不能刷-裸内核/boot-opt6a2-upstream.raw.img" \
            "-ctl-控制版(能开机)|$K/images/不能刷-裸内核/boot-CONTROL-opt5src-rebuilt.raw.img"; do
  n=${pair%%|*}; f=${pair#*|}
  [ -f "$f" ] || { echo "##### $n  文件缺失: $f"; continue; }
  out=$(bash "$V" "$f" "" "$n" 2>&1)
  echo "##### $n"
  echo "$out" | grep -E "^  (FAIL|PASS) IP6" | sed 's/^/    /'
  echo "$out" | grep "=====" | sed 's/^/    /'
done
