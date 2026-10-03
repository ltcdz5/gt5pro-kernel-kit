#!/usr/bin/env python3
# 通用: 把任意 Image 塞进原厂 boot_a.img 的 v4 布局
import struct, os, sys
DESK = r"C:\Users\USERNAME\Desktop\gt5pro-kernel\images"
STOCK = os.path.join(DESK, "boot_a.img")
NEWK  = sys.argv[1]
OUT   = sys.argv[2]

st = open(STOCK, "rb").read()
kern = open(NEWK, "rb").read()
PART = len(st)
a4096 = lambda x: (x + 4095) & ~4095

ft = st[-64:]
assert ft[:4] == b"AVBf"
ft_vb_off, = struct.unpack(">Q", ft[20:28])
ft_vb_sz,  = struct.unpack(">Q", ft[28:36])
vb = st[ft_vb_off:ft_vb_off+ft_vb_sz]
assert vb[:4] == b"AVB0"

ks = len(kern)
new_vb_off = 4096 + a4096(ks)
assert new_vb_off + ft_vb_sz < PART - 64, "放不下"

out = bytearray(PART)
hdr = bytearray(st[:4096])
struct.pack_into("<I", hdr, 8, ks)
struct.pack_into("<I", hdr, 12, 0)
out[0:4096] = hdr
out[4096:4096+ks] = kern
out[new_vb_off:new_vb_off+ft_vb_sz] = vb
ftn = bytearray(ft)
struct.pack_into(">Q", ftn, 12, new_vb_off)
struct.pack_into(">Q", ftn, 20, new_vb_off)
out[PART-64:PART] = ftn
open(OUT, "wb").write(bytes(out))

d = open(OUT, "rb").read()
ks2, = struct.unpack("<I", d[8:12])
print("内核 %d 字节 -> AVB0 @ %d" % (ks, new_vb_off))
print("回读: size=%d(%s) kernel_size=%d(%s) MZ=%s AVB0=%s footer=%s" % (
    len(d), "OK" if len(d) == PART else "错", ks2, "OK" if ks2 == ks else "错",
    d[4096:4098].hex(), d[new_vb_off:new_vb_off+4], d[-64:-60]))
i = d.find(b"Linux version")
print("版本串: %s" % (d[i:i+90].decode("ascii", "replace") if i > 0 else "无"))
print("写出:", OUT)
