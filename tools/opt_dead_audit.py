#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_dead_audit.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 累计改动 vs opt7-clean(d56788d59)，逐个判"有没有真链接进本机内核镜像"
# 判据：out/vmlinux.a 的成员 = 真进 boot_a；只在 out/ 有 .o 而无成员 = 编成 .ko，带不走；两边都没有 = 本机压根不编
import subprocess, os, sys

TREE = "/home/builder/kwork/cctv18/repo/local/kernel_workspace/common"
BASE = sys.argv[1] if len(sys.argv) > 1 else "d56788d59"

def git(*a):
    r = subprocess.run(["git", *a], cwd=TREE, capture_output=True, text=True)
    if r.returncode:
        print("GIT ERR:", r.stderr.strip()[:300]); sys.exit(1)
    return r.stdout

changed = [f for f in git("diff", "--name-only", BASE + "..HEAD").split("\n") if f.strip()]

vm = os.path.join(TREE, "out", "vmlinux.a")
if not os.path.exists(vm):
    print("缺 out/vmlinux.a，先编一次"); sys.exit(1)
r = subprocess.run(["ar", "t", vm], capture_output=True, text=True)
print("ar rc=%d stderr=%s" % (r.returncode, r.stderr.strip()[:200]))
raw = [l.strip() for l in r.stdout.split("\n") if l.strip()]
def norm(m):
    if "/out/" in m:
        return m.split("/out/", 1)[1]
    return m[4:] if m.startswith("out/") else m
mem = set(norm(m) for m in raw)
print("vmlinux.a 成员=%d  样例=%s" % (len(mem), sorted(mem)[:3]))

shipped, dead_ko, not_compiled, non_c = [], [], [], []
for f in changed:
    if not f.endswith(".c"):
        non_c.append(f); continue
    o = f[:-2] + ".o"
    if o in mem:
        shipped.append(f)
    elif os.path.exists(os.path.join(TREE, "out", o)):
        dead_ko.append(f)
    else:
        not_compiled.append(f)

print("\ntotal changed=%d  .c=%d  non-.c=%d" % (len(changed), len(shipped) + len(dead_ko) + len(not_compiled), len(non_c)))
print("SHIPPED(在 vmlinux.a 里)= %d" % len(shipped))
print("DEAD .ko(编了但刷 boot_a 带不走)= %d" % len(dead_ko))
print("NOT COMPILED(本机压根不编)= %d" % len(not_compiled))
for name, lst in [("DEAD_KO", dead_ko), ("NOT_COMPILED", not_compiled), ("NON_C", non_c)]:
    print("\n== %s ==" % name)
    for f in lst:
        print("  " + f)
os.makedirs("/home/builder/opt-prune", exist_ok=True)
with open("/home/builder/opt-prune/dead_files.txt", "w") as fh:
    fh.write("\n".join(dead_ko + not_compiled) + "\n")
with open("/home/builder/opt-prune/shipped_files.txt", "w") as fh:
    fh.write("\n".join(shipped) + "\n")
print("\n可退清单 -> ~/opt-prune/dead_files.txt (%d)；在镜像清单 -> ~/opt-prune/shipped_files.txt (%d)"
      % (len(dead_ko) + len(not_compiled), len(shipped)))
