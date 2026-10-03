#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/exports_diff.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 导出表逐名对比: opt5(能开) vs opt6(砖) 的 Module.symvers, 点名"opt5 有而 opt6 没有"的符号。
# 再用字符串 intersect 在 7 个裸 Image 里查这些符号到底还进不进 __ksymtab。
BASE=/home/builder/opt5-baseline
WIN='/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/不能刷-裸内核'
ls -l "$BASE/Module.symvers" "$BASE/Module.symvers.opt6" 2>&1

python3 - <<'PY'
import os, subprocess, glob
B='/home/builder/opt5-baseline'
def names(p):
    s=set()
    for L in open(p, errors='replace'):
        f=L.split('\t')
        if len(f)>=4: s.add(f[1])
    return s
a=names(os.path.join(B,'Module.symvers'))
b=names(os.path.join(B,'Module.symvers.opt6'))
print("opt5 导出=%d  opt6 导出=%d" % (len(a), len(b)))
gone=sorted(a-b); new=sorted(b-a)
print(">>> opt5 有而 opt6 没有(=被裁掉的导出) %d 个" % len(gone))
for x in gone: print("     -", x)
print(">>> opt6 新增导出 %d 个" % len(new))
for x in new[:20]: print("     +", x)

probe = gone if gone else ['schedtune_task_boost']
if 'schedtune_task_boost' not in probe: probe.append('schedtune_task_boost')
print()
print("=== 在裸 Image 里查这些符号是否还作为字符串存在(=是否进 __ksymtab_strings) ===")
imgs = sorted(glob.glob('/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/不能刷-裸内核/*.img'))
cache={}
for p in imgs:
    d=open(p,'rb').read()
    cache[os.path.basename(p)]=d
hdr = "%-40s" % "symbol" + "".join("%-14s"%os.path.basename(p).replace('.img','').replace('boot-','')[:12] for p in imgs)
print(hdr)
for s in probe:
    row="%-40s"%s[:40]
    for p in imgs:
        row += "%-14s" % ("有" if s.encode() in cache[os.path.basename(p)] else "无")
    print(row)
PY
