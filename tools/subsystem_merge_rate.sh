#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/subsystem_merge_rate.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 按子系统量 stable 142~145 的"能干净落地"数 —— 判每个方向有没有料可取
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/patches/stable
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null
for v in 142 143 144 145; do xz -dc "$P/patch-6.1.$v.xz" > /tmp/sub$v; done
python3 - <<'PY'
import re, subprocess, os, collections
CWD=os.getcwd()
GROUPS={
 'fs/erofs':[r'^fs/erofs/'],
 'fs/f2fs':[r'^fs/f2fs/'],
 'block':[r'^block/'],
 'mm':[r'^mm/'],
 'net':[r'^net/'],
 'fs/verity+crypto':[r'^fs/verity/',r'^fs/crypto/'],
 'kernel/sched':[r'^kernel/sched/'],
 'arch/arm64(非dts)':[r'^arch/arm64/(?!boot/dts)'],
}
tot={g:[0,0] for g in GROUPS}
rej={g:[] for g in GROUPS}
n=0
for v in ('142','143','144','145'):
    blocks,cur,name=[],None,None
    for L in open('/tmp/sub%s'%v,errors='replace'):
        m=re.match(r'^diff --git a/(\S+)',L)
        if m:
            if cur is not None: blocks.append((name,cur))
            name,cur=m.group(1),[L]
        elif cur is not None: cur.append(L)
    if cur is not None: blocks.append((name,cur))
    for fn,b in blocks:
        if not fn: continue
        for g,pats in GROUPS.items():
            if any(re.match(p,fn) for p in pats):
                n+=1
                p='/tmp/g_%d.diff'%n
                open(p,'w').write(''.join(b))
                r=subprocess.run(['git','apply','--check','--whitespace=nowarn',p],capture_output=True,text=True,cwd=CWD)
                tot[g][0]+=1
                if r.returncode==0: tot[g][1]+=1
                else: rej[g].append(fn)
                break
print("子系统                 补丁内文件  能干净落地  落地率")
for g,(a,b) in tot.items():
    print("  %-22s %-11d %-11d %s%%" % (g,a,b, (0 if not a else round(b*100/a))))
print()
print("=== 能落地的具体文件名(每组前 6) ===")
for g,pats in GROUPS.items():
    pass
PY
echo "=== 顺带: opt10 已落地的 10 个文件之外, erofs/f2fs/block 有没有进来过 ==="
cut -f2 /home/builder/opt10/landed.txt 2>/dev/null | grep -E "^(fs/erofs|fs/f2fs|block)/" | sort -u | sed 's/^/  /'
cut -f2 /home/builder/opt10/landed.txt 2>/dev/null | grep -cE "^(fs/erofs|fs/f2fs|block)/" | sed 's/^/  合计=/'
