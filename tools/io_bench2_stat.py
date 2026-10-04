# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/io_bench2_stat.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import re, statistics as st
P='/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/logs/io-bench2.txt'
L=[l for l in open(P,encoding='utf-8',errors='replace')]
def grab(pat):
    out=[]
    for l in L:
        m=re.search(pat,l)
        if m: out.append(int(m.group(1)))
    return out
p0=grab(r'p0-\d+ ..?=(\d+)ms') or grab(r'p0-\d+ [^\s]+=(\d+)ms')
print('P0 噪声标定 (mq-deadline@ra512 读 x5): %s' % p0)
if p0:
    m0=st.median(p0); band=max(p0)-min(p0)
    print('   中位=%dms  波动带=%dms = 中位数的 %.0f%%   ← 小于这个数的档间差都不算差异' % (m0,band,100*band/m0))
print()
print('P1 写 128MB x3')
print('   %-12s %-18s %6s %8s' % ('调度器','三轮值','中位','对首组'))
base=None
for s in ('mq-deadline','kyber','bfq','none'):
    v=grab(r'w\d '+s+r' (\d+)ms')
    if not v: continue
    m=st.median(v)
    if base is None: base=m
    print('   %-12s %-18s %6d  %+7.1f%%' % (s,str(v),m,100*(m-base)/base))
print()
print('P2 读 128MB x4')
print('   %-12s %-6s %-22s %6s %8s' % ('调度器','ra_kb','四轮值','中位','对首组'))
b2=None
for s in ('mq-deadline','kyber'):
    for ra in ('128','512','1024'):
        v=grab(r'r\d '+s+r' ra='+ra+r' (\d+)ms')
        if not v: continue
        m=st.median(v)
        if b2 is None: b2=m
        print('   %-12s %-6s %-22s %6d  %+7.1f%%' % (s,ra,str(v),m,100*(m-b2)/b2))
print()
allr=p0+grab(r'r\d \S+ ra=\d+ (\d+)ms')
print('读测全局: %d ~ %dms (相差 %.1f 倍);  P0 带宽 %.0f%%' % (min(allr),max(allr),max(allr)/float(min(allr)), 100*(max(p0)-min(p0))/st.median(p0) if p0 else 0))
