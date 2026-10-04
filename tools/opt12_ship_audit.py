# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_ship_audit.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import subprocess, os
T='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
out=subprocess.run(['ar','t',T+'out/vmlinux.a'],capture_output=True,text=True)
if out.returncode!=0:
    print("ar t 失败:", out.stderr.strip()[:200])
    raise SystemExit(1)
mem={l.strip().split('out/',1)[-1] for l in out.stdout.splitlines() if l.strip()}
print("vmlinux.a 成员数=%d  样例=%s" % (len(mem), sorted(mem)[:2]))
changed=[l.strip() for l in open('/tmp/g2.lst') if l.strip()]
inb=[];mod=[]
for f in changed:
    o=f[:-2]+'.o'
    (inb if o in mem else mod).append(f)
print()
print("改动文件=%d" % len(changed))
print("  在 vmlinux.a 内 = 真进 boot 镜像 : %d" % len(inb))
print("  不在 = 编成 .ko, 只刷 boot 带不走  : %d" % len(mod))
print()
print(">>> 带不走的清单(按目录归类):")
import collections
c=collections.Counter('/'.join(m.split('/')[:2]) for m in mod)
for k,v in c.most_common(): print("   %-26s %d" % (k,v))
print()
print(">>> 逐文件:")
for m in sorted(mod): print("   ", m)
open('/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/logs/opt12-not-shipped.txt','w').write('\n'.join(sorted(mod))+'\n')
open('/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/logs/opt12-shipped.txt','w').write('\n'.join(sorted(inb))+'\n')
