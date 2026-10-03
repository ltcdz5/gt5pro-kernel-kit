# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/唤醒源差值分析.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import sys, re

def load(p):
    meta, hdr, rows = [], None, {}
    for ln in open(p, encoding='utf-8', errors='replace'):
        s = ln.rstrip('\n')
        if s.startswith('#'):
            meta.append(s); continue
        t = s.split()
        if not t: continue
        if t[0] == 'name':
            hdr = t; continue
        if hdr is None: continue
        try:
            nums = [float(x) for x in t[1:]]
        except ValueError:
            continue
        rows[t[0]] = nums
    return meta, hdr, rows

mA, hA, A = load(sys.argv[1])
mB, hB, B = load(sys.argv[2])
print('列名:', hA)
print('\n'.join(mA[:4])); print('\n'.join(mB[:4]))

def num(x):
    return int(x) if float(x) == int(float(x)) else x

ua = [l for l in mA if 'uptime=' in l]; ub = [l for l in mB if 'uptime=' in l]
def up(l):
    return float(re.search(r'uptime=([\d.]+)', l).group(1)) if l else None
ta, tb = up(ua[0]) if ua else None, up(ub[0]) if ub else None
win = (tb - ta) if (ta and tb) else None
print('\n静置窗口 = %s s' % ('%.0f' % win if win else '未知'))

cols = hA[1:]
common = [k for k in A if k in B]
only_b = [k for k in B if k not in A]
only_a = [k for k in A if k not in B]
d = {k: [B[k][i] - A[k][i] for i in range(len(cols))] for k in common}

# 找"占用时间"列（6.1 里通常是 total_time / total_time_ms）
ti = None
for i, c in enumerate(cols):
    if 'total_time' in c: ti = i; break
ai = 0  # active_count 一般是第一列

print('\n== 静置期增量排行（按占用时间增量，前 15）==')
print('%-34s %12s %12s' % ('name', 'Δ占用', 'Δ唤醒次数'))
for k in sorted(common, key=lambda x: -(d[x][ti] if ti is not None else 0))[:15]:
    print('%-34s %12.0f %12.0f' % (k, d[k][ti] if ti is not None else 0, d[k][ai]))

if win:
    tot = sum(d[k][ti] for k in common) if ti is not None else 0
    print('\n静置期所有唤醒源占用时间合计 = %.0f（单位同列），占窗口 %.1f%%' % (tot, 100.0 * tot / (win * 1000)))

print('\n== B 里新出现（A 没有）的唤醒源 ==')
print('\n'.join('   ' + k for k in only_b) or '   （无）')
print('== A 有 B 没了 ==')
print('\n'.join('   ' + k for k in only_a) or '   （无）')

print('\n== Δ唤醒次数排行（前 10）==')
for k in sorted(common, key=lambda x: -(d[x][ai]))[:10]:
    print('   %-34s %8.0f' % (k, d[k][ai]))
