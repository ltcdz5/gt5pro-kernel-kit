#!/bin/bash
# 三个砖版的交集 = 嫌疑人。直接把补丁里这几个文件的 hunk 原文打出来, 对着我们的配置判活/死。
echo '=== build_opt6a.sh 与 build_opt6a2.sh 的文件清单 ==='
grep -hE '^A=\(|^A2=\(' /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/build_opt6a.sh \
     /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/build_opt6a2.sh 2>/dev/null | tr -d '\r'
echo
echo '=== opt6(全量25文件) 里有没有这几个 —— 交集判定 ==='
python3 - <<'PY'
import re
a  = ['fs/f2fs/checkpoint.c','block/blk-mq.c','include/linux/blk-mq.h','include/linux/file.h','android/abi_gki_aarch64_oplus']
a2 = ['block/blk-mq.c','include/linux/blk-mq.h','include/linux/file.h','android/abi_gki_aarch64_oplus']
txt = open('/home/builder/opt6_upstream.patch', errors='replace').read()
full = [l[6:].strip() for l in txt.split('\n') if l.startswith('+++ b/')]
inter = set(a) & set(a2) & set(full)
print("  -a   文件数=%d" % len(a))
print("  -a2  文件数=%d" % len(a2))
print("  全量 文件数=%d" % len(full))
print("  >>> 三版交集(共同嫌疑) = %s" % sorted(inter))
PY
echo
echo '=== 这几个 hunk 的原文 ==='
awk '/^\+\+\+ b\/(block\/blk-mq\.c|include\/linux\/blk-mq\.h|include\/linux\/file\.h)$/{p=1} /^\+\+\+ b\//{if($0 !~ /blk-mq|file\.h/) p=0} p' /home/builder/opt6_upstream.patch | head -90
echo
echo '=== 我们的配置里, 这些 hunk 依赖的开关是什么值 ==='
grep -E 'CONFIG_BLK_MQ_USE_LOCAL_THREAD|CONFIG_F2FS_FS=|CONFIG_MULTIUSER|CONFIG_SCHED_DEBUG|CONFIG_PROFILING' /home/builder/opt5-baseline/config | sed 's/^/  /'
