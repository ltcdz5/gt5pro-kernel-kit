#!/bin/bash
T=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
echo '=== 这些构建脚本在不在 ==='
ls -1 "$T" | grep -iE 'opt6|opt7|control' | sed 's/^/  /'
echo
echo '=== build_opt6a2.sh 全文(它定义了 -a2 到底套了哪些文件) ==='
sed -n '1,80p' "$T/build_opt6a2.sh" | tr -d '\r'
echo
echo '=== 上游补丁里有哪些文件 ==='
grep -E '^\+\+\+ ' /home/builder/opt6_upstream.patch | sed 's|^+++ b/||' | nl | sed 's/^/  /'
