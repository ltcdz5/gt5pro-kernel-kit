#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/inventory_stock_only.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 方向2: 只读盘点 —— 原厂开着而我们没开的 config 项, 并判"能不能开"
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
python3 - <<'PY'
import gzip, re, io, subprocess, os
C='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
st = gzip.open('/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/refs/stock_config.gz','rb').read().decode('utf-8','replace')
mine = io.open(os.path.join(C,'out/.config'), encoding='utf-8', errors='replace').read()
def kv(t):
    d={}
    for L in t.splitlines():
        m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L)
        if m: d[m.group(1)]=m.group(2); continue
        m=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L)
        if m: d[m.group(1)]='n'
    return d
S,O=kv(st),kv(mine)
# 原厂=y / 有值, 我们=n 或不存在
cand=[(k,S[k],O.get(k,'<符号不存在>')) for k in S
      if S[k] not in ('n','') and O.get(k,'n')=='n']
print("原厂开着、我们没开 的候选 = %d 项\n" % len(cand))
group=['CPU_FREQ','CPU_IDLE','THERMAL','DEVFREQ','PM_','SUSPEND','WALT','SCHED','CPULIMIT',
       'MEMRECLAIM','SHRINK','LRU','ZSWAP','ZRAM','COMPACT','MM_','VM_','BWMON','IO','BLK_',
       'MQ_IOSCHED','NET','TCP','QFQ','CAKE','WiFi','WLAN','CFG80211','CRYPTO','CRYPTO_ARM','HARDEN']
def hit(k): return [g for g in group if g.lower() in k.lower()]
lines=[]
for k,s,o in sorted(cand):
    # 这个符号在我们树里存不存在(存在=可评估; 不存在=两棵树天然差异, 开不了)
    r=subprocess.run(['grep','-rl','--include=Kconfig*','--include=Makefile','-m1',k[8:],C+'/kernel',C+'/mm',C+'/fs',C+'/net',C+'/lib',C+'/block',C+'/arch/arm64',C+'/drivers'],capture_output=True,text=True)
    exists = '可评估' if r.returncode==0 else '树里无此Kconfig'
    lines.append((exists,k,s))
for want in ('可评估','树里无此Kconfig'):
    sub=[l for l in lines if l[0]==want]
    print("=== %s (%d 项) ===" % (want,len(sub)))
    for _,k,s in sub:
        tags=','.join(hit(k))
        print("   %-52s 原厂=%-14s %s" % (k,s[:14],('['+tags+']') if tags else ''))
    print()
PY
