#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/crc_diff.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
"""crc_diff.py —— 比对两版 vmlinux.symvers，报出【导出符号的 CRC 变化】

用途：改结构体/改原型后，**在跑闸门2 之前**先看清影响面。
      2026-10-03 的 opt39 事故就是靠手工比对发现的：
        struct nf_conntrack_expect 加一个字段 ⇒ 109 个导出符号 CRC 变化，
        其中 39 个【名字里完全看不出来】（__skb_get_hash 经 struct sk_buff 被牵连）。

用法：
    python3 crc_diff.py <旧.symvers> <新.symvers> [--vko-syms <厂商真引用名文件>]

输出：
    1) 新增/消失的导出符号
    2) CRC 变化的符号（按"名字能否看出关联"分类）
    3) 其中被【厂商真引用名】命中的（= 会让厂商 .ko 拒载的危险项）
    4) 退出码：0 = 无 CRC 变化；1 = 有变化但不涉及厂商引用；2 = 有变化且涉及厂商引用（危险）

vmlinux.symvers 格式（tab 分隔）：
    0x<CRC>\t<符号名>\t<模块名>\t<命名空间>
    内建代码的模块名是 "vmlinux"；=m 的是模块名。
"""
import io, os, sys

def load(path):
    """返回 {符号名: (crc, module)}"""
    d = {}
    for line in io.open(path, "r", encoding="utf-8", errors="replace"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 3 and p[2] == "vmlinux":
            d[p[1]] = (p[0], p[2])
    return d

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    old_p, new_p = sys.argv[1], sys.argv[2]
    vko = None
    if "--vko-syms" in sys.argv:
        vko = sys.argv[sys.argv.index("--vko-syms") + 1]
    else:
        # 默认找项目里的权威厂商引用名表
        for c in ("/home/builder/abi/vko_syms_real.txt",
                  os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vendor-ko-symbols-real.txt")):
            if os.path.exists(c):
                vko = c; break

    o, n = load(old_p), load(new_p)
    so, sn = set(o), set(n)
    added, removed = sorted(sn - so), sorted(so - sn)
    changed = sorted(k for k in (so & sn) if o[k][0] != n[k][0])

    vset = set()
    if vko and os.path.exists(vko):
        for line in io.open(vko, "r", encoding="utf-8", errors="replace"):
            s = line.strip()
            if s: vset.add(s)

    print("=" * 78)
    print("crc_diff: %s  →  %s" % (os.path.basename(old_p), os.path.basename(new_p)))
    print("=" * 78)
    print("  旧版 vmlinux 导出 %d   新版 %d   共有 %d" % (len(o), len(n), len(so & sn)))
    print("  新增 %d   消失 %d   ★CRC 变化 %d" % (len(added), len(removed), len(changed)))
    if vko:
        print("  厂商真引用名基准: %s（%d 条）" % (vko, len(vset)))

    def show(title, items, limit=40):
        if not items: return
        print("\n  --- %s（%d）---" % (title, len(items)))
        for k in items[:limit]:
            print("      %s" % k)
        if len(items) > limit:
            print("      … 还有 %d 个" % (len(items) - limit))

    show("新增导出", added)
    show("消失导出", removed)

    if changed:
        # 按"名字里能否看出关联"粗分：含 expect/ct/conntrack/nf_/ext4/jbd2/... 视为"看得出"
        hint = ("expect", "conntrack", "ct_", "nf_", "nat", "ext4", "jbd2", "usb", "zstd",
                "lz4", "xz", "crc", "xxh", "skb", "flow", "sock")
        direct = [k for k in changed if any(h in k for h in hint)]
        indirect = [k for k in changed if k not in direct]
        show("★ CRC 变化的符号 —— 名字里【看得出】关联", direct)
        show("★★ CRC 变化的符号 —— 名字里【看不出】关联（最容易被漏掉）", indirect)

        if vset:
            hit = sorted(k for k in changed if k in vset)
            show("⛔ CRC 变化 且 被【厂商真引用名】命中（会让 .ko 拒载）", hit)
        else:
            hit = []

    print()
    if not changed:
        print("  判定：✅ 导出 CRC 零变化 ⇒ 厂商 493 个 .ko 不受影响")
        return 0
    if hit:
        print("  判定：⛔ 有 %d 个被厂商引用的符号 CRC 变了 ⇒ 必须跑 gate_vko_crc.py 确认拒载模块数" % len(hit))
        return 2
    print("  判定：⚠️ 有 CRC 变化，但未命中厂商真引用名 ⇒ 仍须跑 gate_vko_crc.py 确认")
    return 1

if __name__ == "__main__":
    sys.exit(main())
