#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate0_type_diff.py
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   作用 : 【闸门0】结构级 ABI 预检 —— 比较两份 abidw 生成的 ABI 语料
#   为什么 : 闸门2 只能发现「有厂商模块引用的符号」漂移；本工具直接看类型，
#            能发现全部 ABI 变化（即使当前没有模块引用），并指出是哪个类型/哪个成员造成的。
#   用法 : gate0_type_diff.py <ref.xml> <cand.xml> [vmlinux.symvers]
#   判定 : 与导出符号可达的类型发生任何变化 => 判 FAIL（会破坏厂商模块 CRC 契约）
# ---------------------------------------------------------------------------
import sys, os, xml.etree.ElementTree as ET
from collections import defaultdict, deque

TYPE_TAGS = {
    "struct-decl": "struct", "union-decl": "union", "enum-decl": "enum",
    "typedef-decl": "typedef", "class-decl": "class",
}

def load(path):
    root = ET.parse(path).getroot()
    # 1) 符号 CRC（libabigail 读的是内核 __crc_* => 即 modversions CRC）
    crc = {}
    for s in root.iter("elf-symbol"):
        n = s.get("name")
        if n:
            crc[n] = s.get("crc") or ""
    # 2) 每个元素 id -> 引用的类型 id 集合（包含 id 的元素本身也是类型）
    refs = defaultdict(set)
    ids = {}
    named = {}
    for el in root.iter():
        eid = el.get("id")
        if not eid:
            continue
        ids[eid] = el.tag
        if el.tag in TYPE_TAGS and el.get("name"):
            named[eid] = el.get("name")
        # 关键：把「该类型元素内部出现的一切 type-id」都算作它的引用（含成员、函数参数等）
        # —— 成员 <member> 自己没有 id，必须借祖先的 id 建立边，否则可达性会严重偏小
        for d in el.iter():
            for a in ("type-id", "type"):
                v = d.get(a)
                if v and v.startswith("type-id-"):
                    refs[eid].add(v)
    # 3) 类型「定义指纹」：按名字聚合成员/枚举值，用于判断类型是否变化
    defs = {}
    for el in root.iter():
        if el.tag not in TYPE_TAGS or not el.get("name"):
            continue
        name = el.get("name")
        parts = []
        for m in el.iter():
            if m is el:
                continue
            if m.tag in ("member", "data-member", "enumerator"):
                parts.append("|".join([
                    m.tag, m.get("name") or "", m.get("type-id") or "",
                    m.get("offset-in-bits") or "", m.get("bitsize") or "",
                    m.get("value") or "",
                ]))
        defs[(TYPE_TAGS[el.tag], name)] = tuple(parts)
    # 4) 函数原型：名字 -> 类型 id 列表（参数 + 返回）
    funcs = defaultdict(list)
    for el in root.iter("function-decl"):
        n = el.get("name")
        if not n:
            continue
        tids = []
        for c in el.iter():
            for a in ("type-id", "type"):
                v = c.get(a)
                if v and v.startswith("type-id-"):
                    tids.append(v)
        funcs[n].extend(tids)
    return {"crc": crc, "refs": refs, "named": named, "defs": defs, "funcs": funcs}

def reachable_type_names(corpus, root_tids, limit=200000):
    seen = set()
    names = set()
    dq = deque(root_tids)
    while dq and len(seen) < limit:
        t = dq.popleft()
        if t in seen:
            continue
        seen.add(t)
        nm = corpus["named"].get(t)
        if nm:
            names.add(nm)
        for nx in corpus["refs"].get(t, ()):
            if nx not in seen:
                dq.append(nx)
    return names

def main():
    if len(sys.argv) < 3:
        print("用法: %s <ref.xml> <cand.xml> [vmlinux.symvers]" % os.path.basename(sys.argv[0]))
        return 2
    ref = load(sys.argv[1])
    cand = load(sys.argv[2])
    exported = None
    if len(sys.argv) > 3 and os.path.exists(sys.argv[3]):
        exported = set()
        with open(sys.argv[3]) as f:
            for line in f:
                p = line.split(chr(9))
                if len(p) > 1:
                    exported.add(p[1])
    print("=== 闸门0：结构级 ABI 预检 ===")
    print("  ref  = %s（%d 符号 / %d 类型定义）" % (os.path.basename(sys.argv[1]), len(ref["crc"]), len(ref["defs"])))
    print("  cand = %s（%d 符号 / %d 类型定义）" % (os.path.basename(sys.argv[2]), len(cand["crc"]), len(cand["defs"])))
    # (a) 符号 CRC 漂移
    common = set(ref["crc"]) & set(cand["crc"])
    drifted = sorted(n for n in common if ref["crc"][n] != cand["crc"][n])
    added = sorted(set(cand["crc"]) - set(ref["crc"]))
    gone = sorted(set(ref["crc"]) - set(cand["crc"]))
    print("  CRC 漂移 = %d ｜ 新增符号 = %d ｜ 消失符号 = %d" % (len(drifted), len(added), len(gone)))
    if exported is not None:
        d_exp = [n for n in drifted if n in exported]
        a_exp = [n for n in added if n in exported]
        g_exp = [n for n in gone if n in exported]
        print("  其中【导出】符号：漂移 = %d ｜ 新增 = %d ｜ 消失 = %d" % (len(d_exp), len(a_exp), len(g_exp)))
    # (b) 类型定义变化
    tcommon = set(ref["defs"]) & set(cand["defs"])
    tchanged = sorted(k for k in tcommon if ref["defs"][k] != cand["defs"][k])
    tadded = sorted(set(cand["defs"]) - set(ref["defs"]))
    tgone = sorted(set(ref["defs"]) - set(cand["defs"]))
    print("  类型变化 = %d ｜ 新增类型 = %d ｜ 消失类型 = %d" % (len(tchanged), len(tadded), len(tgone)))
    if tchanged:
        print("  --- 变化的类型（最多 25 条）---")
        for kind, name in tchanged[:25]:
            r = set(ref["defs"][(kind, name)])
            c = set(cand["defs"][(kind, name)])
            add = [x for x in c - r][:3]
            rem = [x for x in r - c][:3]
            det = []
            for x in add:
                det.append("+" + x.split("|")[0] + ":" + (x.split("|")[1] or "?"))
            for x in rem:
                det.append("-" + x.split("|")[0] + ":" + (x.split("|")[1] or "?"))
            print("      %-8s %-42s %s" % (kind, name, " ".join(det)))
    # (c) 可达半径：哪些函数（导出符号）依赖了变化的类型
    if tchanged and exported is not None:
        changed_names = set(n for _, n in tchanged)
        hit = []
        for fn in exported:
            tids = cand["funcs"].get(fn)
            if not tids:
                continue
            rn = reachable_type_names(cand, tids)
            if rn & changed_names:
                hit.append(fn)
        print("  可达半径：%d 个导出符号依赖了上述变化类型" % len(hit))
        if hit:
            print("      " + ", ".join(hit[:20]) + (" …" if len(hit) > 20 else ""))
    verdict = "PASS" if (not tchanged and not tadded and not tgone and not drifted and not added and not gone) else "FAIL"
    print("  判定（结构级）：%s" % ("PASS —— 结构体/类型零变化" if verdict == "PASS" else "FAIL —— 有类型或 CRC 变化，需人工判断是否触及 hub 类型"))
    rc = 0 if verdict == "PASS" else 1
    print("退出码 %d（0=结构无变化, 1=有变化）" % rc)
    return rc

if __name__ == "__main__":
    sys.exit(main())
