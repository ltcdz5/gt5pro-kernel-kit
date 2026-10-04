#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/repack_any.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
# 通用: 把任意 Image 塞进原厂 boot_a.img 的 v4 布局
# 用法: python repack_any.py <裸Image> <输出img> [原厂boot_a.img]   (缺省用 images/boot_a.img)
#
# ---- 2026-10-01 加固(见 kernel-kit/工具链审计-20261001.md §二.④) ----
# 原版能在"没塞进内核"的情况下报成功(实测: 喂 0 字节文件 -> 产出 201MB 件、
# kernel_size=0(OK)、exit 0)。原因: 回读只判 len(d)==PART(因 out=bytearray(PART) 必然成立)
# 和 ks2==ks(自洽), 而 MZ/AVB0/footer 三个字段只打印、无断言。
# 现补: 输入必须是真 arm64 Image(MZ 魔数 + 非空 + 版本串可读)、
#       产出件的内核区必须与输入逐字节相同、尺寸必须等于分区大小。
# 另: vbmeta 是原样搬走只改位置, AVB hash descriptor 仍描述旧内容 =>
#       产出件 AVB 不合法, 只在解锁 BL 下能起。这里显式打印该事实, 不再用"回读 OK"暗示它合法。
import struct, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_STOCK = os.path.join(os.path.dirname(os.path.dirname(HERE)), "images", "boot_a.img")  # opt47 修正：images/ 在 kernel-kit 的上一级
if len(sys.argv) < 3:
    print("用法: %s <裸Image> <输出img> [原厂boot_a.img]" % os.path.basename(sys.argv[0]))
    sys.exit(2)
NEWK  = sys.argv[1]
OUT   = sys.argv[2]
STOCK = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_STOCK

if not os.path.exists(NEWK):
    print("错误: 裸 Image 不存在: %s" % NEWK); sys.exit(2)
if not os.path.exists(STOCK):
    print("错误: 原厂底图不存在: %s" % STOCK); sys.exit(2)

st = open(STOCK, "rb").read()
kern = open(NEWK, "rb").read()
PART = len(st)
a4096 = lambda x: (x + 4095) & ~4095

# ---- 输入校验: 必须是真内核, 不是 0 字节/文本 ----
if len(kern) == 0:
    print("错误: 裸 Image 是 0 字节 -> 拒绝出件"); sys.exit(2)
if kern[:2] != b"MZ":
    print("错误: 裸 Image 不以 MZ 开头 (前 2 字节 = %r) -> 不是 arm64 Image, 拒绝出件"
          % kern[:2]); sys.exit(2)
_vi = kern.find(b"Linux version")
if _vi <= 0:
    print("错误: 裸 Image 里找不到 'Linux version' 串 -> 拒绝出件"); sys.exit(2)

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

# ---- 产出校验: 逐条断言, 不再"只打印" ----
d = open(OUT, "rb").read()
ks2, = struct.unpack("<I", d[8:12])
ok = True
if len(d) != PART:
    print("❌ 产出件尺寸 %d != 分区大小 %d" % (len(d), PART)); ok = False
if ks2 != ks:
    print("❌ 回读 kernel_size=%d != 输入 %d" % (ks2, ks)); ok = False
if d[4096:4096+ks] != kern:
    print("❌ 产出件内核区与输入不逐字节相同"); ok = False
if d[4096:4098] != b"MZ":
    print("❌ 产出件内核区开头不是 MZ"); ok = False
if d[new_vb_off:new_vb_off+4] != b"AVB0":
    print("❌ vbmeta 魔数 AVB0 不在预期位置"); ok = False
if d[-64:-60] != b"AVBf":
    print("❌ footer 魔数 AVBf 不在末尾"); ok = False

print("内核 %d 字节 -> AVB0 @ %d" % (ks, new_vb_off))
print("回读: size=%d  kernel_size=%d  MZ=%s  AVB0=%s  footer=%s"
      % (len(d), ks2, d[4096:4098].decode('ascii','replace'),
         d[new_vb_off:new_vb_off+4].decode('ascii','replace'),
         d[-64:-60].decode('ascii','replace')))
print("内核区与输入逐字节比对: %s" % ("相同 ✅" if d[4096:4096+ks] == kern else "不同 ❌"))
i = d.find(b"Linux version")
print("版本串: %s" % (d[i:i+90].decode("ascii", "replace") if i > 0 else "无"))
print("⚠️  vbmeta 未重签: AVB hash descriptor 仍描述旧内容 => 产出件 AVB 不合法, 只在解锁 BL 下能起")
print("写出:", OUT)
sys.exit(0 if ok else 1)
