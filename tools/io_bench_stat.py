# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/io_bench_stat.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import re, statistics as st
P='/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/logs/io-sched-bench.txt'
rows=[]
for L in open(P,encoding='utf-8',errors='replace'):
    m=re.match(r'\s*(\d)\s+(\S+)\s+(\S+)\s+(写|读)=(\d+)ms',L)
    if m: rows.append((int(m.group(1)),m.group(2),m.group(3),m.group(4),int(m.group(5))))
def tab(op):
    print("=== %s 测 512MB · 三轮 min/中位/极差 ===" % op)
    print("   %-11s %-7s %6s %6s %8s %8s" % ("调度器","ra_kb","min","中位","极差","对首组"))
    keys=[]
    for _,s,r,o,_ in rows:
        if o==op and (s,r) not in keys: keys.append((s,r))
    base=None
    for s,r in keys:
        v=[t for _,ss,rr,oo,t in rows if oo==op and ss==s and rr==r]
        if not v: continue
        mn=min(v)
        if base is None: base=mn
        print("   %-11s %-7s %6d %6d %8d  %+6.1f%%" % (s,r,mn,int(st.median(v)),max(v)-min(v),(mn-base)*100.0/base))
tab('写'); print(); tab('读')
rd=[t for _,_,_,o,t in rows if o=='读']
print("\n读测全局: 最快 %dms 最慢 %dms = 相差 %.1f 倍  ← 这就是本次环境的噪声量级" % (min(rd),max(rd),max(rd)/float(min(rd))))
wr=[t for _,_,_,o,t in rows if o=='写']
print("写测全局: 最快 %dms 最慢 %dms = 相差 %.1f 倍" % (min(wr),max(wr),max(wr)/float(min(wr))))
