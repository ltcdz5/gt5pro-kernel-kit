#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate_vko_crc.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
"""
闸门(真值版): 厂商 .ko 期望的 modversions CRC vs 候选内核导出的 CRC

为什么需要它(而不是只比符号集合):
  内核 check_version() 在 CONFIG_MODVERSIONS=y 下, 拿厂商 .ko 的 __versions 里
  记的 CRC 与内核 __kcrctab 比, 不等就拒绝装载:
      "xxx: disagrees about version of symbol yyy"
  gate_new_exports.py 只看"谁在/谁不在", 完全看不见"符号还在但 CRC 变了"。
  实测: opt15 上 7 个符号 CRC 漂移 => WiFi(mac80211/qca_cld3_*) + 蓝牙 + 网络加速
        共 9 个模块拒绝装载, lsmod 从 621 掉到 607。

__versions 节格式(每个条目 64 字节):
    u32 crc (little-endian)  +  char name[60] (NUL 结尾, 实际 56 字节有效 + 对齐)
  (内核 include/linux/modversions.h: struct modversion_info { unsigned long crc; char name[MODULE_NAME_LEN]; };
   MODULE_NAME_LEN = 56, 但对齐到 8 => 4 字节 crc + 4 字节填充 + 56 字节 name = 64)

用法:
  gate_vko_crc.py <候选 vmlinux.symvers> <厂商.ko目录> [更多目录...]
退出码: 0=没有模块会挂, 1=有模块会挂, 2=输入错误
"""
import os
import struct
import sys

SHT_STRTAB = 3


def elf_sections(data):
    """返回 [(name, off, size), ...]；只做 64 位小端 ELF。"""
    if data[:4] != b"\x7fELF":
        return []
    if data[4] != 2 or data[5] != 1:      # 64 位 / 小端
        return []
    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, = struct.unpack_from("<H", data, 0x3A)
    e_shnum, = struct.unpack_from("<H", data, 0x3C)
    e_shstrndx, = struct.unpack_from("<H", data, 0x3E)
    if e_shoff == 0 or e_shnum == 0:
        return []
    shs = []
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        if base + 64 > len(data):
            break
        name_off, = struct.unpack_from("<I", data, base)
        sh_type, = struct.unpack_from("<I", data, base + 4)
        sh_off, = struct.unpack_from("<Q", data, base + 0x18)
        sh_size, = struct.unpack_from("<Q", data, base + 0x20)
        shs.append((name_off, sh_type, sh_off, sh_size))
    if e_shstrndx >= len(shs):
        return []
    stroff = shs[e_shstrndx][2]
    out = []
    for name_off, sh_type, sh_off, sh_size in shs:
        end = data.find(b"\0", stroff + name_off)
        nm = data[stroff + name_off:end].decode("ascii", "replace") if end > 0 else ""
        out.append((nm, sh_off, sh_size))
    return out


def read_versions(path):
    """返回 {symbol: crc}；没有 __versions 或为空则返回 {}。"""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    for nm, off, size in elf_sections(data):
        if nm != "__versions" or size == 0:
            continue
        out = {}
        for p in range(off, off + size - 63, 64):
            crc, = struct.unpack_from("<I", data, p)
            raw = data[p + 8:p + 8 + 56]
            name = raw.split(b"\0", 1)[0].decode("ascii", "replace")
            if name:
                out[name] = crc
        return out
    return {}


def read_crc(path):
    out = {}
    with open(path, errors="replace") as f:
        for line in f:
            t = line.rstrip("\n").split("\t")
            if len(t) >= 4 and t[1] and t[2] == "vmlinux":
                out[t[1]] = int(t[0], 16)
    return out


def main():
    if len(sys.argv) < 3:
        print("用法: %s <候选 vmlinux.symvers> <厂商.ko目录> [更多目录...]"
              % os.path.basename(sys.argv[0]))
        return 2
    cand_p, dirs = sys.argv[1], sys.argv[2:]
    if not os.path.exists(cand_p) or os.path.getsize(cand_p) == 0:
        print("错误: 候选 %s 不存在或为空 -> 拒绝出结论" % cand_p); return 2
    cand = read_crc(cand_p)
    if not cand:
        print("错误: 候选解析出 0 个 vmlinux 导出"); return 2

    kos = []
    for d in dirs:
        if not os.path.isdir(d):
            print("错误: 目录不存在 %s" % d); return 2
        for root, _dd, files in os.walk(d):
            for fn in files:
                if fn.endswith(".ko"):
                    kos.append(os.path.join(root, fn))
    if not kos:
        print("错误: 没找到任何 .ko"); return 2

    print("候选 %s: vmlinux 导出 %d" % (os.path.basename(cand_p), len(cand)))
    print("厂商模块 %d 个" % len(kos))
    print("=" * 88)

    broken = {}
    n_checked = 0
    n_with_crc = 0
    for ko in kos:
        vers = read_versions(ko)
        if vers is None:
            continue
        n_checked += 1
        if not vers:
            continue
        n_with_crc += 1
        bad = []
        for sym, want in vers.items():
            have = cand.get(sym)
            if have is None:
                continue           # 符号不导出 => 走 weak-NULL 路径, 由另一道闸门管
            if have != want:
                bad.append((sym, want, have))
        if bad:
            broken[ko] = bad

    print("解析成功 %d 个；其中带非空 __versions 的 %d 个" % (n_checked, n_with_crc))
    print("会拒绝装载的模块 = %d" % len(broken))
    print("=" * 88)

    if broken:
        print("★ 以下模块在本候选内核上会 `disagrees about version of symbol` 而拒绝装载：\n")
        for ko in sorted(broken):
            print("  %s   (%d 个符号不符)" % (ko, len(broken[ko])))
            for sym, want, have in sorted(broken[ko])[:8]:
                print("        %-40s 厂商期望=0x%08x  本内核=0x%08x" % (sym, want, have))
            if len(broken[ko]) > 8:
                print("        ... 另有 %d 个" % (len(broken[ko]) - 8))
        allsym = sorted({s for v in broken.values() for s, _, _ in v})
        print("\n  合计涉及 %d 个符号:" % len(allsym))
        for s in allsym:
            print("      %s" % s)
    else:
        print("✅ 所有厂商模块的 CRC 都能对上，没有模块会因 CRC 被拒载")

    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
