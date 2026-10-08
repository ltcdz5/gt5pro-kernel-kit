#!/usr/bin/env python3
# gt5pro-kernel-kit / tools/gate_all_modules.py
# 全量厂商模块审计：逐 .ko 比对 __versions 期望值与内核 vmlinux.symvers
# 同时报「符号缺失」与「CRC 不符」——gate2 只查已存在符号的 CRC，缺符号是盲区。
# 用法: python3 tools/gate_all_modules.py <tree_dir> <vendor-ko_dir...>
import struct, io, os, glob, re
T = '/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
os.chdir(T)
exp = {}
for line in io.open('out/vmlinux.symvers', encoding='utf-8', errors='replace'):
    p = line.split(chr(9))
    if len(p) >= 2: exp[p[1]] = p[0]
print('内核导出 =', len(exp))
def vers(path):
    try:
        d = io.open(path, 'rb').read()
        e_shoff, = struct.unpack_from('<Q', d, 0x28)
        es, en, sx = struct.unpack_from('<HHH', d, 0x3a)
        secs = []
        for i in range(en):
            off = e_shoff + i * es
            nm, typ, fl, ad, o, sz, lk, info, al, ent = struct.unpack_from('<IIQQQQIIQQ', d, off)
            secs.append((nm, o, sz))
        sh = secs[sx]
        def sn(n):
            b = d[sh[1] + n:]; return b[:b.index(b'\0')].decode('utf-8', 'replace')
        for (nm, o, sz) in secs:
            if sn(nm) == '__versions':
                out = []
                for i in range(0, sz, 64):
                    crc, = struct.unpack_from('<Q', d, o + i)
                    n2 = d[o + i + 8: o + i + 8 + 56].split(b'\0')[0].decode('utf-8', 'replace')
                    if n2: out.append(('0x%08x' % crc, n2))
                return out
    except Exception:
        return None
    return []
bad = []
miss = {}
n = 0
for root in ['/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm', '/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/system_dlkm']:
    for path in glob.glob(root + '/*.ko'):
        e = vers(path)
        if not e: continue
        n += 1
        m = [x for x in e if x[1] not in exp]
        c = [(x, exp[x[1]]) for x in e if x[1] in exp and exp[x[1]] != x[0]]
        if m or c:
            bad.append((os.path.basename(path), len(m), len(c)))
            for _, nm in m[:6]: miss[nm] = miss.get(nm, 0) + 1
print('扫描模块 =', n, ' 有问题的模块 =', len(bad))
for b in bad[:14]: print('   %-42s 缺失=%-3d CRC不符=%d' % b)
print('--- 缺失符号出现次数 top 12 ---')
for nm, k in sorted(miss.items(), key=lambda x: -x[1])[:12]: print('   %-44s %d 个模块' % (nm, k))