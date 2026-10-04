#!/bin/bash
# 正确 magic = 0xEB9F。在裸 Image 里定位 BTF 并抠出来, 用 pahole 验能否读
set -e
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
mkdir -p /home/builder/abi/btf

echo "=== 先在 ELF 抽出的已知 BTF 上确认头格式 ==="
od -An -tx1 -N24 /tmp/t.btf

echo "=== 扫 7 个裸 Image ==="
python3 - "$TREE/out/arch/arm64/boot/Image" $WIN/*.img <<'PY'
import sys,struct,os
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
OUT='/home/builder/abi/btf'
for p in sys.argv[1:]:
    d=open(p,'rb').read()
    hits=[]; i=0
    while True:
        j=d.find(PAT,i)
        if j<0: break
        hits.append(j); i=j+1
    name=os.path.basename(p).replace('.img','').replace('.raw','')
    print("%-40s 大小=%-10d 命中=%d %s" % (name, len(d), len(hits), [hex(h) for h in hits[:3]]))
    for h in hits[:1]:
        magic,ver,flags,hdr_len = struct.unpack_from('<HBB I', d, h)
        type_off,type_len,str_off,str_len = struct.unpack_from('<IIII', d, h+8)
        total = hdr_len + type_off + type_len + str_off + str_len
        print("    hdr_len=%d type_len=%d str_len=%d total=%d(%.2fMB) 尾对齐余=%d"
              % (hdr_len,type_len,str_len,total,total/1048576.0,len(d)-h-total))
        blob=d[h:h+total]
        open(os.path.join(OUT, name+'.btf'),'wb').write(blob)
PY
echo "=== 抠出来的文件 ==="
ls -l /home/builder/abi/btf/
echo "=== pahole 能否读 opt5 那份 ==="
pahole -C task_struct /home/builder/abi/btf/boot-opt5-ltcdz5.btf 2>&1 | head -4
echo "=== 全量 struct 计数 (opt5 vs opt6a2) ==="
for f in boot-opt5-ltcdz5 boot-opt6a2-upstream; do
  echo "$f: $(pahole /home/builder/abi/btf/$f.btf 2>/dev/null | grep -c '^struct ')"
done
