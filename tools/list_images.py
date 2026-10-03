#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/list_images.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import os, re, hashlib, sys
D = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\USERNAME\Desktop\gt5pro-kernel\images"
for n in sorted(os.listdir(D)):
    if not n.endswith('.img'):
        continue
    p = os.path.join(D, n)
    d = open(p, 'rb').read()
    m = re.search(rb'Linux version (\S+ \S+)', d)
    banner = m.group(1).decode('ascii', 'replace') if m else '-'
    print("%-34s %11d  %s  %s" % (n, len(d), hashlib.md5(d).hexdigest()[:12], banner))
