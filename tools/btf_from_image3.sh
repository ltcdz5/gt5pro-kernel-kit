#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/btf_from_image3.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 从 7 个裸 Image 里抠出 BTF 类型表并验可读
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
D=/home/builder/abi/btf
mkdir -p "$D"

echo "=== 扫裸 Image 里的 BTF 头 (magic 0xEB9F) ==="
python3 - "$TREE/out/arch/arm64/boot/Image" "$WIN"/*.img <<PY
import sys,struct,os
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
OUT="$D"
for p in sys.argv[1:]:
    d=open(p,'rb').read()
    hits=[]; i=0
    while True:
        j=d.find(PAT,i)
        if j<0: break
        hits.append(j); i=j+1
    name=os.path.basename(p)
    for q in ('.img','raw.','.boot-'): pass
    name=name.replace('boot-','').replace('.img','').replace('.raw','')
    print("%-34s 大小=%-10d 命中=%d %s" % (name,len(d),len(hits),[hex(h) for h in hits[:3]]))
    if hits:
        h=hits[0]
        hdr_len,=struct.unpack_from('<I',d,h+4+2)
        type_off,type_len,str_off,str_len=struct.unpack_from('<IIII',d,h+8)
        total=24+type_off+type_len+str_off+str_len
        open(os.path.join(OUT,name+'.btf'),'wb').write(d[h:h+total])
        print("     total=%d (%.2f MB)  写到 %s.btf" % (total,total/1048576.0,name))
PY
echo "=== 落盘 ==="
ls -l "$D"
echo "=== pahole 读得动吗 ==="
for f in "$D"/*.btf; do
  printf '%-46s struct数=%s  task_struct=%s\n' "$(basename $f)" \
    "$(pahole "$f" 2>/dev/null | grep -c '^struct ')" \
    "$(pahole -C task_struct "$f" 2>/dev/null | grep -m1 'task_struct;' | tr -s ' ')"
done
