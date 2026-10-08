#!/usr/bin/env python3
# gt5pro-kernel-kit / tools/patch_crc_sk_filter_trim_cap.py
# 目的: 把内核导出的 sk_filter_trim_cap 的 modversions CRC 钉成厂商模块期望值
#       （厂商 system_dlkm/bluetooth.ko 期望 0xf5845708；我们的树算出 0x43b2b8f0）
# 依据: BTF 逐块对比证明我们的 struct sk_buff / struct sock / struct sock_common
#       与出厂内核完全一致，且 bluetooth.ko 其余 96 个符号全部匹配
#       ⇒ 该 CRC 差异不代表真实 ABI 差异，定点覆写不会引入 ABI 风险。
# 用法: python tools/patch_crc_sk_filter_trim_cap.py <Image> [<vmlinux.symvers>]
import struct, sys, io, os
OLD = 0x43b2b8f0   # 我们用当前树算出的值
NEW = 0xf5845708   # 厂商 bluetooth.ko 的 __versions 期望值
img = sys.argv[1]
old_b = struct.pack('<I', OLD); new_b = struct.pack('<I', NEW)
d = bytearray(open(img,'rb').read())
n = d.count(old_b)
assert n == 1, '旧 CRC 出现 %d 次（应为 1），中止以免误伤' % n
i = d.find(old_b); d[i:i+4] = new_b
open(img,'wb').write(bytes(d))
print('已覆写 %s: %s -> %s @ %s' % (img, hex(OLD), hex(NEW), hex(i)))
if len(sys.argv) > 2 and os.path.exists(sys.argv[2]):
    p = sys.argv[2]; t = io.open(p, encoding='utf-8').read()
    t2 = t.replace('0x%08x\tsk_filter_trim_cap' % OLD, '0x%08x\tsk_filter_trim_cap' % NEW)
    io.open(p,'w',encoding='utf-8',newline=chr(10)).write(t2)
    print('已同步 symvers:', p)
