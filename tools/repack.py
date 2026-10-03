#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/repack.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 通用 boot v4 重打包: repack.py <原厂boot> <新裸Image> <输出>
import struct, sys, os
STOCK, NEWK, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
st = open(STOCK, "rb").read(); kern = open(NEWK, "rb").read(); PART = len(st)
a4096 = lambda x: (x + 4095) & ~4095
ft = st[-64:]
assert ft[:4] == b"AVBf", "原厂 footer magic 不对"
ft_vb_off, = struct.unpack(">Q", ft[20:28]); ft_vb_sz, = struct.unpack(">Q", ft[28:36])
vb = st[ft_vb_off:ft_vb_off+ft_vb_sz]
assert vb[:4] == b"AVB0", "原厂 vbmeta magic 不对"
ks = len(kern); new_vb_off = 4096 + a4096(ks)
out = bytearray(PART)
hdr = bytearray(st[:4096])
struct.pack_into("<I", hdr, 8, ks); struct.pack_into("<I", hdr, 12, 0)
out[0:4096] = hdr; out[4096:4096+ks] = kern
out[new_vb_off:new_vb_off+ft_vb_sz] = vb
ftn = bytearray(ft)
struct.pack_into(">Q", ftn, 12, new_vb_off); struct.pack_into(">Q", ftn, 20, new_vb_off)
out[PART-64:PART] = ftn
open(OUT, "wb").write(bytes(out))
d = open(OUT, "rb").read()
ks2, = struct.unpack("<I", d[8:12])
ok = (len(d) == PART and ks2 == ks and d[4096:4098] == b"MZ" and d[new_vb_off:new_vb_off+4] == b"AVB0" and d[-64:-60] == b"AVBf")
i = d.find(b"Linux version")
print("内核 %d 字节 -> AVB0 @ %d" % (ks, new_vb_off))
print("回读: %s" % ("全部通过 OK" if ok else "!! 有问题"))
print("版本串: %s" % d[i:i+70].decode("ascii", "replace"))
print("写出: %s (%d 字节)" % (OUT, len(d)))
