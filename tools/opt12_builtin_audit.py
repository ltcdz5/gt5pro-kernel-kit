# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_builtin_audit.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import os, re, subprocess
T='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
SM=T+'out/System.map'
syms=set()
for L in open(SM,encoding='utf-8',errors='replace'):
    p=L.split()
    if len(p)>=3: syms.add(p[2])
files=[l.strip() for l in open('/tmp/g2.lst',encoding='utf-8',errors='replace') if l.strip()]
inside=[]; maybe_mod=[]
for f in files:
    p=T+f
    if not os.path.exists(p): continue
    txt=open(p,encoding='utf-8',errors='replace').read()
    names=re.findall(r'^[A-Za-z_][A-Za-z0-9_ \*]*?\b([a-z_][A-Za-z0-9_]{4,})\s*\(', txt, re.M)
    cand=[n for n in dict.fromkeys(names) if n in syms]
    if cand: inside.append((f,cand[0]))
    else: maybe_mod.append(f)
print("改动文件总数=%d" % len(files))
print("  在 vmlinux 符号表里找到本文件定义的函数(=确认进本机镜像) = %d" % len(inside))
print("  一个都没找到(= 很可能是 =m 模块, 刷 boot 带不走) = %d" % len(maybe_mod))
print("\n>>> 疑似未进镜像的文件:")
for f in maybe_mod: print("   ", f)
