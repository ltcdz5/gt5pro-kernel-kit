#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_report_prune.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 报告：opt12 相对 opt11 的净增量按子系统分组；并把 28 个"白改"归到引入它的那一版
import subprocess, collections, sys

TREE = "/home/builder/kwork/cctv18/repo/local/kernel_workspace/common"
OPT11 = "4faf90660"
OPT12 = "bbe1b4de1"
BASE = "d56788d59"

def git(*a):
    return subprocess.run(["git", *a], cwd=TREE, capture_output=True, text=True).stdout

def subsys(f):
    top = f.split("/")
    return top[0] if len(top) == 1 else "/".join(top[:2]) if top[0] in ("net", "arch", "security", "fs", "kernel") else top[0]

# 1) opt12 相对 opt11 的增量（只算真进镜像的 97 个）
shipped = [l.strip() for l in open("/home/builder/opt-prune/shipped_files.txt") if l.strip()]
in12 = set(l.strip() for l in git("diff", "--name-only", OPT11 + ".." + OPT12).split("\n") if l.strip())
new_ship = [f for f in shipped if f in in12]
print("== opt12 相对 opt11：真进镜像的新文件 %d 个，按子系统 ==" % len(new_ship))
c = collections.Counter(subsys(f) for f in new_ship)
for k, v in sorted(c.items(), key=lambda x: -x[1]):
    print("  %-28s %d" % (k, v))

# 2) 行数规模
st = git("--no-pager", "diff", "--shortstat", OPT11 + ".." + OPT12)
print("\nopt11..opt12 全量 shortstat:" + st.strip())

# 3) 28 个白改的归属
dead = [l.strip() for l in open("/home/builder/opt-prune/dead_files.txt") if l.strip()]
print("\n== %d 个白改分别来自哪一版 ==" % len(dead))
rows = collections.Counter()
for f in dead:
    lg = git("log", "--oneline", BASE + ".." + OPT12, "--", f).strip().split("\n")
    rows[(lg[-1].split(" ", 1)[0], lg[-1].split(" ", 1)[1][:46]) if lg else ("?", "?")] += 1
for (h, msg), n in rows.most_common():
    print("  %-10s %-48s %d 个文件" % (h, msg, n))
for f in dead:
    lg = git("log", "--format=%h", BASE + ".." + OPT12, "--", f).strip().split("\n")
    print("    %-40s <- %s" % (f, lg[-1] if lg and lg[0] else "?"))
