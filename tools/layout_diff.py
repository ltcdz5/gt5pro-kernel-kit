#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/layout_diff.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 结构体布局对比闸: 从每个裸 Image 内嵌的 BTF 里导出"每个 struct 的 size + 每个字段的偏移/宽度",
# 以 opt5(已知能开机) 为基准, 点名哪些 struct 的布局变了。
# 用法: python3 layout_diff.py <基准.btf> <候选1.btf> [候选2.btf ...]
import subprocess, sys, os, re

D = '/home/builder/abi/lay'
os.makedirs(D, exist_ok=True)

def dump(btf):
    name = os.path.basename(btf).replace('.btf', '')
    out = os.path.join(D, name + '.txt')
    if not os.path.exists(out) or os.path.getsize(out) == 0:
        txt = subprocess.run(['pahole', btf], capture_output=True, text=True).stdout
        open(out, 'w').write(txt)
    return name, out

FIELD = re.compile(r'^(.*?)\s*/\*\s*(\d+)\s+(\d+)\s*\*/')
SIZE = re.compile(r'/\*\s*size:\s*(\d+)')

def parse(path):
    """-> {struct_name: (size, [(field, off, width), ...])}"""
    res = {}
    cur = None
    fields = []
    for line in open(path, errors='replace'):
        s = line.rstrip('\n')
        m = re.match(r'^(struct|union|enum)\s+([A-Za-z0-9_]+)\s*\{', s)
        if m:
            if cur is not None:
                res[cur[1]] = (cur[2], fields)
            cur = m.groups() + (None,)
            cur = (m.group(1), m.group(2), None)
            fields = []
            continue
        if cur is None:
            continue
        if s.startswith('};') or s.startswith('} ') or s.strip() == '};':
            m2 = SIZE.search(s)
            res[cur[1]] = (int(m2.group(1)) if m2 else -1, fields)
            cur = None
            fields = []
            continue
        fm = FIELD.match(s)
        if fm:
            fname = fm.group(1).strip().rstrip(';')
            fname = fname.split()[-1].lstrip('*').split('[')[0]
            fields.append((fname, int(fm.group(2)), int(fm.group(3))))
        elif 'size:' in s:
            m2 = SIZE.search(s)
            if m2:
                res[cur[1]] = (int(m2.group(1)), fields)
                cur = None
                fields = []
    if cur is not None:
        res[cur[1]] = (-1, fields)
    return res

base_path = sys.argv[1]
base_name, base_txt = dump(base_path)
BASE = parse(base_txt)
print("基准 %s: 解析出 %d 个类型" % (base_name, len(BASE)))
print("=" * 74)

for cand in sys.argv[2:]:
    cname, ctxt = dump(cand)
    C = parse(ctxt)
    changed_size, changed_layout, gone, new = [], [], [], []
    for k, v in BASE.items():
        if k not in C:
            gone.append(k); continue
        if C[k][0] != v[0]:
            changed_size.append((k, v[0], C[k][0]))
        elif C[k][1] != v[1]:
            changed_layout.append(k)
    for k in C:
        if k not in BASE:
            new.append(k)
    print("%s  (类型数 %d)" % (cname, len(C)))
    print("   size 变了      : %d" % len(changed_size))
    print("   字段偏移/宽度变: %d" % len(changed_layout))
    print("   基准有它没有   : %d      新增类型: %d" % (len(gone), len(new)))
    for k, a, b in changed_size[:25]:
        print("      [size] %-40s %d -> %d" % (k, a, b))
    for k in changed_layout[:25]:
        print("      [layout] %s" % k)
    print("-" * 74)
