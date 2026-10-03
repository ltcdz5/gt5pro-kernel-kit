#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt8_whats_new.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 抽出 opt8 实际套用的 13 个文件的 hunk(函数上下文 + 新增行), 供逐条说明"新增了什么"
import re, collections, sys

KEEP = set("""arch/arm/mm/fault.c arch/arm64/mm/fault.c arch/powerpc/mm/fault.c
arch/riscv/mm/fault.c arch/s390/mm/fault.c arch/x86/mm/fault.c fs/eventpoll.c fs/pipe.c
include/linux/file.h include/linux/mm_types.h mm/filemap.c mm/memory.c net/unix/garbage.c""".split())

txt = open('/home/builder/opt6_upstream.patch', errors='replace').read().split('\n')
per = collections.OrderedDict(); cur = None; hunk = None
for L in txt:
    m = re.match(r'^\+\+\+ b/(.*)$', L)
    if m:
        cur = m.group(1).strip(); per.setdefault(cur, []); hunk = None; continue
    if cur in KEEP:
        m2 = re.match(r'^@@ .* @@ (.*)$', L)
        if m2:
            hunk = m2.group(1).strip()[:60]
            per[cur].append(('FN', hunk)); continue
        if L.startswith('+') and not L.startswith('+++'):
            s = L[1:].strip()
            if s and not s.startswith('*'):
                per[cur].append(('+', s[:110]))
        elif L.startswith('-'):
            s = L[1:].strip()
            if s and not s.startswith('*'):
                per[cur].append(('-', s[:110]))

for f, items in per.items():
    pl = sum(1 for k, _ in items if k == '+'); mi = sum(1 for k, _ in items if k == '-')
    print("=" * 76)
    print("%s      +%d/-%d" % (f, pl, mi))
    shown = 0
    for k, s in items:
        if k == 'FN':
            print("   ── 函数: %s" % s)
        else:
            if shown < 9:
                print("   %s %s" % ('+' if k == '+' else '-', s))
                shown += 1
