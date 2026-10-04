#!/bin/bash
# 验一件事: 裸 Image 里能不能直接抠出 BTF, 以及 pahole 认不认裸 BTF 文件
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
IMG=$TREE/out/arch/arm64/boot/Image
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"

echo "=== 0) 工具在不在 ==="
which llvm-objcopy pahole abidw abidiff 2>&1

echo "=== 1) 从 ELF vmlinux 抽 .BTF (用 llvm-objcopy, 之前 gnu objcopy 不认 aarch64) ==="
cd "$TREE"
llvm-objcopy --dump-section .BTF=/tmp/t.btf out/vmlinux 2>&1 | head -3
ls -l /tmp/t.btf 2>/dev/null
echo "--- 头 16 字节 ---"
od -An -tx1 -N16 /tmp/t.btf 2>/dev/null

echo "=== 2) pahole 认不认这个裸 BTF ==="
pahole -F btf -C task_struct /tmp/t.btf 2>&1 | head -6
echo "--- 不加 -F btf ---"
pahole -C task_struct /tmp/t.btf 2>&1 | head -6

echo "=== 3) 直接在裸 Image 里找 BTF 头(magic 97eb ver1 hdr_len=24) ==="
python3 - "$IMG" "$WIN/boot-opt5-ltcdz5-raw.img" "$WIN/boot-opt6a2-upstream.raw.img" <<'PY'
import sys,struct
PAT=bytes([0x97,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
for p in sys.argv[1:]:
    d=open(p,'rb').read()
    hits=[]; i=0
    while True:
        j=d.find(PAT,i)
        if j<0: break
        hits.append(j); i=j+1
    print("%-64s 大小=%d  命中=%d 处 %s" % (p.split('/')[-1], len(d), len(hits), [hex(h) for h in hits[:4]]))
    for h in hits[:2]:
        hdr=d[h:h+40]
        magic,ver,flags,hdr_len=struct.unpack_from('<HBB I',hdr,0)
        type_off,type_len,str_off,str_len=struct.unpack_from('<IIII',hdr,8)
        total=hdr_len+type_off+type_len+str_off+str_len
        print("   @%#x  type_off=%d type_len=%d str_off=%d str_len=%d  total=%d (%.1fMB)  距文件尾=%d"
              % (h,type_off,type_len,str_off,str_len,total,total/1048576.0,len(d)-h-total))
PY
