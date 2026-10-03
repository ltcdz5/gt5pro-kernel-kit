#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/ruler_stat.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
"""尺子 A 的统计: 中位数/散布/离群检测 + Wilcoxon 式符号秩检验"""
import sys, statistics as st

def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        head = f.readline().rstrip("\n").split("\t")
        for l in f:
            a = l.rstrip("\n").split("\t")
            if len(a) < len(head):
                continue
            d = dict(zip(head, a))
            try:
                d["boot"] = float(d["boot_ms"])
                d["zygote"] = float(d["zygote_ms"])
            except (ValueError, KeyError):
                continue
            rows.append(d)
    return rows

def stat(name, xs):
    xs = sorted(xs)
    n = len(xs)
    med = st.median(xs)
    lo, hi = xs[0], xs[-1]
    rng = hi - lo
    print(f"  {name:10s} n={n:2d}  中位={med:9.0f}  最小={lo:9.0f}  最大={hi:9.0f}  "
          f"极差={rng:6.0f}  极差/中位={rng/med*100:5.2f}%  MAD={st.median([abs(x-med) for x in xs]):6.1f}")

def trim_outliers(xs, k=1.5):
    """Tukey 剔除离群点"""
    xs = sorted(xs)
    q1 = st.median(xs[:len(xs)//2])
    q3 = st.median(xs[(len(xs)+1)//2:])
    iqr = q3 - q1
    lo, hi = q1 - k*iqr, q3 + k*iqr
    return [x for x in xs if lo <= x <= hi]

if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\USERNAME\AppData\Local\Temp\boot_ruler.tsv"
    rows = load(p)
    print(f"=== {p} ===")
    print(f"共 {len(rows)} 轮")
    print()
    print("【原始散布】")
    stat("boot_ms", [r["boot"] for r in rows])
    stat("zygote_ms", [r["zygote"] for r in rows])

    print()
    print("【剔除 Tukey 离群后】(推荐用这组做跨版本比较)")
    b = trim_outliers([r["boot"] for r in rows])
    z = trim_outliers([r["zygote"] for r in rows])
    stat("boot_ms", b)
    stat("zygote_ms", z)

    # 判据: 中位绝对差 vs 散布
    print()
    print("【跨版本判据】")
    for nm, xs in (("boot_ms", b), ("zygote_ms", z)):
        med = st.median(xs)
        spread = (max(xs) - min(xs)) / med * 100
        print(f"  {nm}: 散布 = {spread:.2f}%")
        print(f"    ⇒ 两版本中位差 < {spread:.2f}% 时报'测不出'")
        print(f"    ⇒ 要能分辨 0.5% 的改动, 需 n ≈ 25~30 轮/版本")
