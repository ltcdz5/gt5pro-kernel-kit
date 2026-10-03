# -*- coding: utf-8 -*-
"""对比 vendor 模块要求的符号 CRC 与本地内核 Module.symvers 导出的 CRC"""
import struct, sys, os

def parse_ko_versions(path):
    d = open(path, 'rb').read()
    if d[:4] != b'\x7fELF':
        raise SystemExit('not ELF: ' + path)
    e_shoff, = struct.unpack_from('<Q', d, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', d, 0x3A)
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        name_off, stype = struct.unpack_from('<II', d, off)
        soff, size = struct.unpack_from('<QQ', d, off + 24)
        secs.append({'name_off': name_off, 'off': soff, 'size': size})
    shstr = secs[e_shstrndx]
    strtab = d[shstr['off']:shstr['off'] + shstr['size']]
    def nm(o):
        e = strtab.index(b'\0', o)
        return strtab[o:e].decode('utf-8', 'replace')
    for s in secs:
        s['name'] = nm(s['name_off'])

    res = {}
    for s in secs:
        if s['name'] != '__versions':
            continue
        blob = d[s['off']:s['off'] + s['size']]
        n64 = len(blob) // 64
        ok = 0
        tmp = {}
        for i in range(n64):
            e = blob[i*64:(i+1)*64]
            crc, = struct.unpack_from('<Q', e, 0)
            rawname = e[8:64].split(b'\0')[0]
            try:
                name = rawname.decode('ascii')
            except Exception:
                break
            if not name:
                break
            tmp[name] = crc & 0xFFFFFFFF
            ok += 1
        res = tmp
        print('  __versions: %d 项 (按 64 字节/项解析成功 %d)' % (n64, ok))
    return res

def parse_symvers(path):
    res = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        f = line.split('\t')
        if len(f) < 2:
            f = line.split()
            if len(f) < 2:
                continue
        try:
            crc = int(f[0], 16)
        except Exception:
            continue
        res[f[1]] = crc
    return res

out = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'crc_report.txt'), 'w', encoding='utf-8')
def w(s):
    out.write(s + '\n')
    print(s)

ko = sys.argv[1]
symvers = sys.argv[2]
w('=== 对比 %s  <->  %s ===' % (os.path.basename(ko), os.path.basename(symvers)))
versions = parse_ko_versions(ko)
mine = parse_symvers(symvers)
w('模块要求符号数: %d' % len(versions))
w('本地内核导出符号数: %d' % len(mine))

match, mismatch, missing = [], [], []
for name, crc in sorted(versions.items()):
    if name not in mine:
        missing.append(name)
    elif mine[name] == crc:
        match.append(name)
    else:
        mismatch.append((name, crc, mine[name]))

w('')
w('一致 : %d' % len(match))
w('CRC不一致: %d' % len(mismatch))
w('内核没有此符号: %d' % len(missing))
w('')
if mismatch:
    w('--- CRC 不一致明细(最多30条) ---')
    for n, a, b in mismatch[:30]:
        w('  %-40s 模块要 %08x  内核给 %08x' % (n, a, b))
if missing:
    w('--- 缺失符号(最多30条) ---')
    for n in missing[:30]:
        w('  ' + n)
if not mismatch and not missing:
    w('*** 全部一致 —— 模块可加载 ***')
out.close()
