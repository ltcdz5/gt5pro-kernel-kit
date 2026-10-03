#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/a4_scope.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# a4 相对 opt5 只多一行 EXPORT_SYMBOL。量它的"越界效应"有多大:
# 1) initcall: 只有 blk-mq 自己变(文件内行号位移) 还是全局启动次序被打乱
# 2) 地址漂移符号的分布(=代码生成被扰动的范围)
import re, collections

def load(p):
    m = {}
    for L in open(p, errors='replace'):
        f = L.split()
        if len(f) == 3:
            try:
                m[f[2]] = (int(f[0], 16), f[1])
            except ValueError:
                pass
    return m

b = load('/home/builder/opt5-baseline/System.map')
c = load('/home/builder/a4probe/System.map.a4')
common = set(b) & set(c)
drift = sorted(k for k in common if b[k][0] != c[k][0])
print("共同符号=%d  地址漂移=%d" % (len(common), len(drift)))

ic_b = {k: v for k, v in b.items() if k.startswith('__initcall__')}
ic_c = {k: v for k, v in c.items() if k.startswith('__initcall__')}
print("\ninitcall 符号数: opt5=%d a4=%d 同名=%d" % (len(ic_b), len(ic_c), len(set(ic_b) & set(ic_c))))
gone = sorted(set(ic_b) - set(ic_c)); new = sorted(set(ic_c) - set(ic_b))
print("消失=%d 新增=%d" % (len(gone), len(new)))
for k in gone[:8]:
    print("   -", k[:80])
for k in new[:8]:
    print("   +", k[:80])

def ranks(d):
    items = sorted(d.items(), key=lambda kv: kv[1][0])
    return {name: i for i, (name, _) in enumerate(items)}

rb, rc = ranks(ic_b), ranks(ic_c)
same = set(rb) & set(rc)
moved = [(k, rb[k], rc[k]) for k in same if rb[k] != rc[k]]
print("\n同名 initcall 里相对次序变了 %d 条 / 共 %d 条" % (len(moved), len(same)))
for k, x, y in sorted(moved, key=lambda t: abs(t[2] - t[1]), reverse=True)[:10]:
    print("   %-60s 秩 %d -> %d" % (k[:60], x, y))

pref = collections.Counter(k.split('.')[0][:16] for k in drift)
print("\n漂移符号前缀 top12:", ", ".join("%s:%d" % ab for ab in pref.most_common(12)))
print("\nblk-mq 相关漂移样例:")
for k in [x for x in drift if 'blk' in x][:10]:
    print("   %-52s %#x -> %#x (差 %d)" % (k, b[k][0], c[k][0], c[k][0] - b[k][0]))
