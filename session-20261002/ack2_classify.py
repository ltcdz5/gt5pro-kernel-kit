#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ACK 第二批补丁分类器。

判据（与 opt14 精简版一致）:
  一条补丁"进不进本机镜像", 看它触碰的文件是否出现在本机构建产物的编译依赖集里。
  依赖集 = out/**/.<obj>.o.cmd 里 deps_<obj> 块列出的全部路径(含头文件)。

输出 TSV: 类别 \t sha \t 触碰文件(逗号分隔)
  类别 ∈ {LAND_APPLY_OK, LAND_CONFLICT, LAND_ALREADY, NOOP}
    LAND_*       至少一个触碰文件在依赖集里
    NOOP         全部触碰文件都不在依赖集里 → 改了也进不了镜像
"""
import os
import re
import sys
import subprocess

K = "/home/builder/kwork/cctv18/repo/local/kernel_workspace/common"
OUT = "/home/builder/opt14/ack2"
PATCHES = "/mnt/c/Users/USERNAME/AppData/Local/Temp/ack_patches2"

os.makedirs(OUT, exist_ok=True)


def norm(p):
    p = p.strip()
    if p.startswith("../"):
        p = p[3:]
    elif p.startswith("./"):
        p = p[2:]
    return p


def collect_deps():
    cache_s = os.path.join(OUT, "compiled_srcs.txt")
    cache_d = os.path.join(OUT, "compiled_deps.txt")
    if os.path.exists(cache_s) and os.path.exists(cache_d) \
            and os.path.getsize(cache_s) > 1000 and os.path.getsize(cache_d) > 1000:
        with open(cache_s) as f:
            srcs = {l.strip() for l in f if l.strip()}
        with open(cache_d) as f:
            deps = {l.strip() for l in f if l.strip()}
        return 0, srcs, deps
    deps = set()
    srcs = set()
    nobj = 0
    for root, _dirs, files in os.walk(os.path.join(K, "out")):
        for fn in files:
            if not fn.endswith(".o.cmd"):
                continue
            nobj += 1
            path = os.path.join(root, fn)
            try:
                with open(path, "r", errors="replace") as f:
                    lines = f.read().split("\n")
            except OSError:
                continue
            cur = False
            for line in lines:
                if line.startswith("source_"):
                    m = re.match(r"^source_[^:]+:=\s*(.+?)\s*$", line)
                    if m:
                        srcs.add(norm(m.group(1)))
                    cur = False
                    continue
                if line.startswith("deps_"):
                    rest = line.split(":=", 1)[1] if ":=" in line else ""
                    cur = rest.rstrip().endswith("\\")
                    body = rest.rstrip().rstrip("\\").strip()
                    if body:
                        deps.add(norm(body))
                    continue
                if line.startswith("cmd_") or line.startswith("savedcmd_"):
                    cur = False
                    continue
                if cur:
                    s = line.rstrip()
                    if s.rstrip().endswith("\\"):
                        s = s.rstrip()[:-1].strip()
                    else:
                        cur = False
                    if s and not s.startswith("$"):
                        deps.add(norm(s))
    deps = {d for d in deps if re.search(r"\.(c|h|S|s|lds)$", d)}
    srcs = {s for s in srcs if re.search(r"\.(c|S|s)$", s)}
    return nobj, srcs, deps


def patch_files(p):
    out = []
    try:
        with open(p, "r", errors="replace") as f:
            for line in f:
                if line.startswith("diff --git "):
                    parts = line.split()
                    if len(parts) >= 4:
                        a = parts[2]
                        if a.startswith("a/"):
                            a = a[2:]
                        out.append(a)
    except OSError:
        pass
    return out


def main():
    nobj, srcs, deps = collect_deps()
    print(f"[依赖集] .o.cmd 文件数={nobj}  编译源={len(srcs)}  依赖(含头文件)={len(deps)}")
    with open(os.path.join(OUT, "compiled_srcs.txt"), "w") as f:
        f.write("\n".join(sorted(srcs)) + "\n")
    with open(os.path.join(OUT, "compiled_deps.txt"), "w") as f:
        f.write("\n".join(sorted(deps)) + "\n")

    # 自检
    for probe in ["mm/truncate.c", "include/linux/mm.h", "fs/f2fs/segment.c",
                  "kernel/sched/fair.c", "net/netfilter/nf_conntrack_core.c",
                  "drivers/scsi/sd.c", "fs/ext4/inode.c", "kernel/bpf/verifier.c",
                  "net/ipv6/exthdrs.c", "drivers/ufs/core/ufshcd.c"]:
        print(f"   自检 {probe:46s} {'在' if probe in (srcs | deps) else '不在'}")

    rows = []
    allset = srcs | deps
    print(f"[判据集] 编译源 ∪ 依赖头 = {len(allset)}")
    for fn in sorted(os.listdir(PATCHES)):
        if not fn.endswith(".patch"):
            continue
        sha = fn[:-6]
        files = patch_files(os.path.join(PATCHES, fn))
        hit = [x for x in files if x in allset]
        if not hit:
            cat = "NOOP"
        else:
            r = subprocess.run(["git", "apply", "--check", os.path.join(PATCHES, fn)],
                               cwd=K, capture_output=True)
            if r.returncode == 0:
                cat = "LAND_APPLY_OK"
            else:
                r3 = subprocess.run(["git", "apply", "--check", "-R", os.path.join(PATCHES, fn)],
                                    cwd=K, capture_output=True)
                cat = "LAND_ALREADY" if r3.returncode == 0 else "LAND_CONFLICT"
        rows.append((cat, sha, ",".join(hit) if hit else ",".join(files)))

    rows.sort()
    with open(os.path.join(OUT, "classify.tsv"), "w") as f:
        for r in rows:
            f.write("\t".join(r) + "\n")

    from collections import Counter
    c = Counter(r[0] for r in rows)
    print()
    print(f"[分类结果] 共 {len(rows)} 条")
    for k, v in c.most_common():
        print(f"   {k:16s} {v}")
    print()
    print("[LAND_APPLY_OK 触碰的顶层目录]")
    c2 = Counter()
    for cat, sha, files in rows:
        if cat == "LAND_APPLY_OK":
            for x in files.split(","):
                parts = x.split("/")
                c2["/".join(parts[:2]) if len(parts) > 1 else parts[0]] += 1
    for k, v in c2.most_common(30):
        print(f"   {k:40s} {v}")


if __name__ == "__main__":
    main()
