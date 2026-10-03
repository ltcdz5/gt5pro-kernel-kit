#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""算"碰过任何改动头文件"的补丁集合 —— 这是保证 CRC 不变的上界。"""
import os
import subprocess

K = "/home/builder/kwork/cctv18/repo/local/kernel_workspace/common"
PATCHES = "/mnt/c/Users/USERNAME/AppData/Local/Temp/ack_patches2"
LIST = "/home/builder/opt14/ack2/apply_list.txt"
OUT = "/home/builder/opt15"

r = subprocess.run(["git", "status", "--porcelain"], cwd=K, capture_output=True, text=True)
changed = sorted({l[3:].strip() for l in r.stdout.split("\n") if len(l) > 3})
headers = [f for f in changed if f.endswith(".h")]
print(f"改动文件 {len(changed)} 个, 其中头文件 {len(headers)} 个:")
for h in headers:
    print("   ", h)

pat_files = {}
for sha in (l.strip() for l in open(LIST) if l.strip()):
    fs = []
    try:
        for line in open(os.path.join(PATCHES, sha + ".patch"), errors="replace"):
            if line.startswith("diff --git "):
                p = line.split()
                if len(p) >= 4 and p[2].startswith("a/"):
                    fs.append(p[2][2:])
    except OSError:
        pass
    pat_files[sha] = fs

subj = {}
for line in open(os.path.join(OUT, "opt15_subjects.tsv"), errors="replace"):
    a = line.rstrip("\n").split("\t")
    if len(a) >= 2:
        subj[a[0]] = a[1]

hset = set(headers)
touch_hdr = {sha: set(fs) & hset for sha, fs in pat_files.items() if set(fs) & hset}
print(f"\n★ 碰过改动头文件的补丁 = {len(touch_hdr)} 条 (占 {len(pat_files)} 条的 {100*len(touch_hdr)/len(pat_files):.0f}%)")
for sha in sorted(touch_hdr, key=lambda x: (-len(touch_hdr[x]), x)):
    print(f"  {sha}  {subj.get(sha,'?')}")
    for f in sorted(touch_hdr[sha]):
        print(f"        {f}")

with open(os.path.join(OUT, "crc_revert_superset.txt"), "w") as f:
    for sha in sorted(touch_hdr):
        f.write(sha + "\n")

# 剩余可保留的
keep = [s for s in pat_files if s not in touch_hdr]
with open(os.path.join(OUT, "crc_keep.txt"), "w") as f:
    for sha in sorted(keep):
        f.write(sha + "\n")
print(f"\n保留 {len(keep)} 条, 退掉 {len(touch_hdr)} 条")
print(f"已写出 {OUT}/crc_revert_superset.txt 与 {OUT}/crc_keep.txt")
