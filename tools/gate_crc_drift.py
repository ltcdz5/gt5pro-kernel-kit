#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate_crc_drift.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
"""
闸门: modversions CRC 漂移
   判据 = { 候选导出 CRC != 基准导出 CRC } ∩ { 厂商 .ko 引用过的符号名 }

为什么需要它:
  gate_new_exports.py 只比"导出集合"(谁在/谁不在), 看不见"符号还在但 CRC 变了"。
  而内核 check_version() 在 CONFIG_MODVERSIONS=y 下会拿厂商 .ko 的 __versions 里
  记的 CRC 和本内核的 CRC 比, 不等就拒绝装载:
      "xxx: disagrees about version of symbol yyy"
  后果 = 该厂商模块直接不加载(实测 opt15 上 WiFi/蓝牙全挂)。
  CRC 由 genksyms 从"声明"算出, 改函数体不改 CRC, 改原型/结构体定义会改。

用法:
  gate_crc_drift.py <候选 vmlinux.symvers> [基准 Module.symvers] [厂商引用名表]
退出码: 0=无危险漂移, 1=有危险漂移, 2=输入错误
"""
import sys
import os

BASE_DEFAULT = '/home/builder/opt5-baseline/Module.symvers'
VKO_DEFAULT = '/home/builder/abi/vko_syms.txt'


def read_crc(path):
    """返回 {name: (crc, module)}，只收 module=='vmlinux' 的行。"""
    out = {}
    with open(path, errors='replace') as f:
        for line in f:
            t = line.rstrip('\n').split('\t')
            if len(t) >= 4 and t[1] and t[2] == 'vmlinux':
                out[t[1]] = t[0]
    return out


def main():
    if len(sys.argv) < 2:
        print("用法: %s <候选 vmlinux.symvers> [基准 Module.symvers] [厂商引用名表]"
              % os.path.basename(sys.argv[0]))
        return 2
    cand_p = sys.argv[1]
    base_p = sys.argv[2] if len(sys.argv) > 2 else BASE_DEFAULT
    vko_p = sys.argv[3] if len(sys.argv) > 3 else VKO_DEFAULT

    for p, what in ((cand_p, '候选'), (base_p, '基准'), (vko_p, '厂商引用名表')):
        if not os.path.exists(p):
            print("错误: %s %s 不存在" % (what, p)); return 2
        if os.path.getsize(p) == 0:
            print("错误: %s %s 是 0 字节" % (what, p)); return 2

    cand = read_crc(cand_p)
    base = read_crc(base_p)
    vko = set(x.strip() for x in open(vko_p, errors='replace') if x.strip())
    if not cand or not base:
        print("错误: 解析出 0 个 vmlinux 导出 -> 拒绝出结论"); return 2

    common = set(cand) & set(base)
    drift = sorted(s for s in common if cand[s] != base[s])
    drift_hit = [s for s in drift if s in vko]
    added = sorted(set(cand) - set(base))
    gone = sorted(set(base) - set(cand))

    print("候选 %s: vmlinux 导出 %d" % (os.path.basename(cand_p), len(cand)))
    print("基准 %s: vmlinux 导出 %d" % (os.path.basename(base_p), len(base)))
    print("厂商引用名表: %d 个" % len(vko))
    print("=" * 84)
    print("共同导出        = %d" % len(common))
    print("CRC 漂移        = %d" % len(drift))
    print("其中厂商引用    = %d   <-- 这些符号的厂商模块会拒绝装载" % len(drift_hit))
    print("新增导出(不在基准)= %d   消失导出 = %d" % (len(added), len(gone)))
    print("=" * 84)

    if drift_hit:
        print("★ 危险漂移 (厂商模块会 `disagrees about version of symbol`):")
        for s in drift_hit:
            print("    %-44s 基准=%-12s 候选=%s" % (s, base[s], cand[s]))
    else:
        print("✅ 无危险 CRC 漂移")

    # 参考: 没被厂商引用的漂移(不影响装载)
    other = [s for s in drift if s not in vko]
    if other:
        print()
        print("(参考) 未被厂商引用的漂移 %d 个, 不影响模块装载, 列出前 20:" % len(other))
        for s in other[:20]:
            print("    %-44s 基准=%-12s 候选=%s" % (s, base[s], cand[s]))

    return 1 if drift_hit else 0


if __name__ == '__main__':
    sys.exit(main())
