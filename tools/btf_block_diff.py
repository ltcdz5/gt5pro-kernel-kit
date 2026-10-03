# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/btf_block_diff.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import re
def blocks(p):
    d={}; name=None; buf=[]
    for L in open(p,encoding='utf-8',errors='replace'):
        m=re.match(r'^(struct|union|enum)\s+([A-Za-z0-9_]+)\s*\{', L)
        if m:
            if name and name not in d: d[name]=''.join(buf)
            name=m.group(2); buf=[L]; continue
        if name is not None:
            buf.append(L)
            if L.rstrip()=='};':
                if name not in d: d[name]=''.join(buf)
                name=None; buf=[]
    return d
a=blocks('/home/builder/abi/full/opt11.txt')
b=blocks('/home/builder/abi/full/opt12.txt')
print("opt11 类型块=%d  opt12 类型块=%d" % (len(a),len(b)))
diff=[k for k in set(a)|set(b) if a.get(k)!=b.get(k)]
print("\n>>> 内容真的不同的结构体 = %d 个" % len(diff))
for k in sorted(diff):
    sa=re.search(r'/\* size: (\d+)',a.get(k,'')); sb=re.search(r'/\* size: (\d+)',b.get(k,''))
    print("   %-28s size %s -> %s" % (k, sa.group(1) if sa else '新出现', sb.group(1) if sb else '新出现'))
print("\n>>> page_pool 两边原文对照:")
for tag,src in (('opt11',a),('opt12',b)):
    t=src.get('page_pool','(无)')
    print("--- %s ---" % tag)
    print('\n'.join('   '+l for l in t.splitlines()[:24]))
