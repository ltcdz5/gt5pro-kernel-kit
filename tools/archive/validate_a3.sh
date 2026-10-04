#!/bin/bash
BASE=/home/builder/opt5-baseline
P=/home/builder/a3probe
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
echo '=== 1) 编译器指纹(必须 = Android clang 17.0.2, builder@) ==='
strings -a "$P/Image.a3" | grep -m1 'Linux version'
echo
echo '=== 2) config 差异行数(应为 0) ==='
diff "$BASE/config" "$TREE/out/.config" | grep -E '^[<>]' | head -12
echo "  差异行数=$(diff "$BASE/config" "$TREE/out/.config" | grep -cE '^[<>]')"
echo
echo '=== 3) 导出表逐名差异: a3 vs opt5 ==='
python3 - <<'PY'
def names(p):
    s=set()
    for L in open(p, errors='replace'):
        f=L.rstrip('\n').split('\t')
        if len(f)>=4: s.add(f[1])
    return s
a=names('/home/builder/opt5-baseline/Module.symvers')
c=names('/home/builder/a3probe/Module.symvers.a3')
print("  opt5=%d  a3=%d  新增=%d  消失=%d" % (len(a), len(c), len(c-a), len(a-c)))
for x in sorted(c-a): print("     +", x)
for x in sorted(a-c): print("     -", x)
PY
echo
echo '=== 4) a3 的 BTF 类型空间 vs opt5(抽 BTF 后全类型比) ==='
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images
mkdir -p /home/builder/abi/btf
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/a3probe/Image.a3','rb').read()
h=d.find(PAT)
if h<0: print("  !! 没找到 BTF"); raise SystemExit
type_off,type_len,str_off,str_len=struct.unpack_from('<IIII', d, h+8)
total=24+type_off+type_len+str_off+str_len
open('/home/builder/abi/btf/opt6a3-split.btf','wb').write(d[h:h+total])
print("  BTF @%#x total=%d" % (h,total))
PY
pahole /home/builder/abi/btf/opt6a3-split.btf > /home/builder/abi/full/opt6a3-split.txt 2>/dev/null
pahole /home/builder/abi/btf/opt5-ltcdz5-raw.btf > /home/builder/abi/full/opt5-ltcdz5-raw.txt 2>/dev/null
echo "  行数: a3=$(wc -l < /home/builder/abi/full/opt6a3-split.txt)  opt5=$(wc -l < /home/builder/abi/full/opt5-ltcdz5-raw.txt)"
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5-ltcdz5-raw.txt /home/builder/abi/full/opt6a3-split.txt | grep -cE '^[<>]')"
diff /home/builder/abi/full/opt5-ltcdz5-raw.txt /home/builder/abi/full/opt6a3-split.txt | grep -E '^[<>]' | head -20 | sed 's/^/    /'
echo
echo '=== 5) 可刷件在位确认 ==='
ls -l "$WIN/试验-a3-未真机验证.img" 2>&1
md5sum "$WIN/试验-a3-未真机验证.img" 2>/dev/null
