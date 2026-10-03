#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""定位危险 CRC 漂移符号由哪些补丁引起。

1) 用 llvm-nm 扫描 out/**/*.o, 建立 符号 -> 定义它的目标文件 的映射(权威)。
2) 取该 .o 的 .o.cmd 依赖集(全部头文件) 与本次改动文件取交集。
3) 反查补丁。
"""
import os
import subprocess
import sys
from collections import defaultdict

K = "/home/builder/kwork/cctv18/repo/local/kernel_workspace/common"
PATCHES = "/mnt/c/Users/USERNAME/AppData/Local/Temp/ack_patches2"
LIST = "/home/builder/opt14/ack2/apply_list.txt"
OUT = "/home/builder/opt15"

SYMS = ["__skb_get_hash", "nf_ct_delete", "tcf_action_exec",
        "tcf_exts_validate", "tcf_exts_destroy", "tcf_exts_dump", "tcf_exts_dump_stats"]

NM = "/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin/llvm-nm"


def build_sym_map():
    """符号 -> 目标文件(相对 out/)。用 llvm-nm 扫全部 .o。"""
    print("[1] 扫描 out/**/*.o 建立 符号->目标文件 映射 ...")
    objs = []
    for root, _d, files in os.walk(os.path.join(K, "out")):
        if "/tools/" in root.replace("\\", "/"):
            continue
        for fn in files:
            if fn.endswith(".o") and fn not in ("vmlinux.o", "built-in.a") \
                    and not fn.startswith(".tmp_vmlinux"):
                objs.append(os.path.join(root, fn))
    print(f"    目标文件 {len(objs)} 个")
    want = set(SYMS)
    found = {}
    # 分批交给 llvm-nm
    B = 400
    for i in range(0, len(objs), B):
        batch = objs[i:i + B]
        try:
            r = subprocess.run([NM, "--defined-only"] + batch,
                               capture_output=True, text=True, timeout=300)
        except Exception as e:
            print("    nm 失败:", e); continue
        cur = None
        for line in r.stdout.split("\n"):
            if not line.strip():
                continue
            if line.endswith(":") and not line.startswith(" "):
                cur = line[:-1]
                continue
            parts = line.split()
            if len(parts) >= 3:
                name = parts[-1]
                if name in want and name not in found:
                    found[name] = os.path.relpath(cur, os.path.join(K, "out")) if cur else "?"
        if i % 2000 == 0:
            print(f"    ...{i}/{len(objs)}")
    for s in SYMS:
        print(f"    {s:22s} -> {found.get(s, '★未找到')}")
    return found


def main():
    sym2obj = build_sym_map()

    # .o.cmd 索引
    cmd_of = {}
    for root, _d, files in os.walk(os.path.join(K, "out")):
        for fn in files:
            if fn.endswith(".o.cmd"):
                obj = fn[1:-4]                     # 去掉前导点 与 .cmd
                rel = os.path.relpath(os.path.join(root, obj), K)
                if rel.startswith("out" + os.sep):
                    rel = rel[4:]
                cmd_of[rel.replace(os.sep, "/")] = os.path.join(root, fn)
    print(f"\n[2] .o.cmd 索引 {len(cmd_of)} 个")

    def deps_of(obj):
        p = cmd_of.get(obj)
        if not p:
            return set(), False
        s = set()
        cur = False
        for line in open(p, errors="replace").read().split("\n"):
            if line.startswith("deps_"):
                rest = line.split(":=", 1)[1] if ":=" in line else ""
                cur = rest.rstrip().endswith("\\")
                continue
            if cur:
                t = line.rstrip()
                if t.rstrip().endswith("\\"):
                    t = t.rstrip()[:-1].strip()
                else:
                    cur = False
                if t and not t.startswith("$"):
                    t = t.strip()
                    if t.startswith("../"):
                        t = t[3:]
                    s.add(t)
        return s, True

    r = subprocess.run(["git", "status", "--porcelain"], cwd=K, capture_output=True, text=True)
    changed = {l[3:].strip() for l in r.stdout.split("\n") if len(l) > 3}
    print(f"[3] 本次改动文件 {len(changed)} 个")

    union = set()
    print("\n[4] 每个危险符号的受影响改动文件:")
    for sym in SYMS:
        obj = sym2obj.get(sym)
        if not obj:
            print(f"    {sym:22s} ★ 没定位到目标文件"); continue
        d, ok = deps_of(obj)
        d.add(obj[:-2] + ".c")
        hit = d & changed
        union |= hit
        print(f"    {sym:22s} {obj:34s} 依赖 {len(d):5d} 个 (解析{'成功' if ok else '失败'}), 命中改动 {len(hit)} 个")
        for h in sorted(hit):
            print(f"          {h}")
    print(f"\n[5] 风险改动文件并集 = {len(union)} 个")

    pat_files = {}
    for sha in (l.strip() for l in open(LIST) if l.strip()):
        fs = []
        try:
            for line in open(os.path.join(PATCHES, sha + ".patch"), errors="replace"):
                if line.startswith("diff --git "):
                    parts = line.split()
                    if len(parts) >= 4 and parts[2].startswith("a/"):
                        fs.append(parts[2][2:])
        except OSError:
            pass
        pat_files[sha] = fs

    subj = {}
    for line in open(os.path.join(OUT, "opt15_subjects.tsv"), errors="replace"):
        a = line.rstrip("\n").split("\t")
        if len(a) >= 2:
            subj[a[0]] = a[1]

    sus = {sha: set(fs) & union for sha, fs in pat_files.items() if set(fs) & union}
    print(f"\n★ 必须退掉的补丁 {len(sus)} 条:\n")
    for sha in sorted(sus, key=lambda x: (-len(sus[x]), x)):
        print(f"  {sha}  {subj.get(sha,'?')}")
        for f in sorted(sus[sha]):
            print(f"        {f}")
    with open(os.path.join(OUT, "crc_revert.txt"), "w") as f:
        for sha in sorted(sus):
            f.write(sha + "\n")
    print(f"\n已写出 {OUT}/crc_revert.txt ({len(sus)} 条)")


if __name__ == "__main__":
    main()
