#!/bin/bash
# 原厂 boot_a.img 里找 FDT(魔数 d00dfeed), 解出 reserved-memory / chosen,
# 回答一个问题: 内核死掉之后, 机器自己有没有留下一块能读回来的日志区。
python3 - <<'PY'
import struct, os, re
CANDS = [
 r"C:\Users\xutengfa\Desktop\gt5pro-kernel\images\boot_a.img",
 r"C:\Users\xutengfa\Desktop\gt5pro-kernel\images\不能刷-裸内核\boot-opt5-ltcdz5-raw.img",
]
MAGIC = bytes([0xd0,0x0d,0xfe,0xed])

def walk(d, off, total):
    """返回 (name, 相对父节点路径) 列表 + 结构解析"""
    ts, tos,  = struct.unpack_from('>II', d, off+4)
    est, eos, lts, = struct.unpack_from('>III', d, off+20)
    p = off + tos
    end_types = off + tos + ts
    strings = off + lts
    stack = []
    out = []
    while p < end_types:
        while p < end_types and d[p] == 0: p += 1
        if p >= end_types: break
        tag = d[p]; p += 4
        if tag == 1:                       # FDT_BEGIN_NODE
            e = d.index(b'\0', p); name = d[p:e].decode('ascii','replace'); p = e + 1
            p = (p + 3) & ~3
            stack.append(name)
            out.append(('/'.join(stack), 'node'))
        elif tag == 2:                     # FDT_END_NODE
            if stack: stack.pop()
        elif tag == 3:                     # FDT_PROP
            len_, nameoff = struct.unpack_from('>II', d, p); p += 8
            val = d[p:p+len_]; p += len_
            p = (p + 3) & ~3
            e = d.index(b'\0', strings+nameoff)
            key = d[strings+nameoff:e].decode('ascii','replace')
            out.append(('/'.join(stack+[key]), 'prop', val[:64].hex(), len_))
        elif tag == 4:                     # FDT_NOP
            continue
        else:
            break
    return out

for path in CANDS:
    if not os.path.exists(path):
        print("缺文件:", path); continue
    d = open(path,'rb').read()
    hits = [m.start() for m in re.finditer(re.escape(MAGIC), d)]
    print("="*72)
    print("%s  大小=%d  FDT魔数命中=%d 处 %s" % (os.path.basename(path), len(d), len(hits),
          [hex(h) for h in hits[:6]]))
    for h in hits[:3]:
        try:
            sz = struct.unpack_from('>I', d, h+4)[1] if False else None
            totalsz = struct.unpack_from('>I', d, h+4)[0]
        except Exception:
            continue
        try:
            entries = walk(d, h, len(d))
        except Exception as e:
            print("   @%#x 解析失败: %s" % (h, e)); continue
        print("   @%#x 节点/属性数=%d" % (h, len(entries)))
        for e in entries:
            p = e[0]
            if 'reserved-memory' in p or 'chosen' in p or 'pstore' in p.lower() or 'ramoops' in p.lower() \
               or 'log@' in p or 'dfm' in p or 'dun' in p or 'memory@' == p.split('/')[-1]:
                print("      %-72s %s" % (p, (e[2] if len(e)>2 else ''))[:200])
PY
