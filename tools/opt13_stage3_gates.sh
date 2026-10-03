#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_stage3_gates.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt13 阶段3：三道闸 + 与 opt12 的导出/BTF 对比（不刷机，纯静态）
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
B=/home/builder/opt13base
D=/home/builder/abi/btf
F=/home/builder/abi/full
V=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/vendor-ko-symbols.txt
K=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
mkdir -p "$D" "$F"
cd "$T" || exit 1

echo "=== 0) 产物身份 ==="
echo "Image 大小=$(stat -c%s out/arch/arm64/boot/Image)  opt12=$(stat -c%s "$B/Image.opt12")"
grep -aoE "Linux version [ -~]{0,130}" out/arch/arm64/boot/Image | head -1
ls -l out/vmlinux.symvers | awk '{print "vmlinux.symvers mtime="$6" "$7" "$8}'

echo "=== 1) 导出表逐名对比（消失/新增/CRC 变） ==="
awk '{print $2" "$3}' "$B/vmlinux.symvers.opt12" | sort > /tmp/o12.txt
awk '{print $2" "$3}' out/vmlinux.symvers | sort > /tmp/o13.txt
cut -d' ' -f1 /tmp/o12.txt > /tmp/n12.txt; cut -d' ' -f1 /tmp/o13.txt > /tmp/n13.txt
comm -23 /tmp/n12.txt /tmp/n13.txt > /tmp/gone.txt
comm -13 /tmp/n12.txt /tmp/n13.txt > /tmp/added.txt
join -j1 /tmp/o12.txt /tmp/o13.txt > /tmp/both.txt
awk '$2!=$3' /tmp/both.txt | wc -l | sed 's/^/CRC 变化符号数=/'
echo "opt12 导出=$(wc -l < /tmp/n12.txt)  opt13 导出=$(wc -l < /tmp/n13.txt)"
echo "消失=$(wc -l < /tmp/gone.txt)  新增=$(wc -l < /tmp/added.txt)"
echo "--- 消失的符号里有多少是厂商 .ko 引用过的(必须 0) ---"
grep -Fxf "$V" /tmp/gone.txt | wc -l
head -5 /tmp/gone.txt
cp /tmp/gone.txt "$B/exports_gone.txt"; cp /tmp/added.txt "$B/exports_added.txt"
echo "--- kfence 两个符号还在吗 ---"
grep -E "kfence_sample_interval|__kfence_pool" out/vmlinux.symvers | cut -f2,3

echo "=== 2) 新增导出闸（老规矩） ==="
python3 "$K/tools/gate_new_exports.py" 2>&1 | tail -5

echo "=== 3) BTF 全类型对比（关 UBSAN 会不会动布局） ==="
python3 - out/arch/arm64/boot/Image "$D/opt13.btf" <<'PY'
import sys,struct
p,outp=sys.argv[1],sys.argv[2]
d=open(p,'rb').read()
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
h=d.find(PAT)
assert h>=0, "找不到 BTF 头"
to,tl,so,sl=struct.unpack_from('<IIII',d,h+8)
total=24+to+tl+so+sl
open(outp,'wb').write(d[h:h+total])
print("BTF 偏移=%d total=%d (%.2f MB)"%(h,total,total/1048576.0))
PY
pahole "$D/opt13.btf" > "$F/opt13.txt" 2>/dev/null
echo "opt13 类型行数=$(wc -l < "$F/opt13.txt")  opt12=$(wc -l < "$F/opt12.txt")"
diff "$F/opt12.txt" "$F/opt13.txt" > "$B/btf_raw.diff" 2>&1
echo "BTF 原始差异行数=$(wc -l < "$B/btf_raw.diff")"
python3 "$K/tools/btf_block_diff13.py" 2>/dev/null || python3 - <<'PY'
import re
def blocks(p):
    d={}; name=None; buf=[]
    for L in open(p,encoding='utf-8',errors='replace'):
        m=re.match(r'^(struct|union|enum)\s+([A-Za-z0-9_]+)\s*\{', L)
        if m:
            if name and name not in d: d[name]=''.join(buf)
            name=m.group(2); buf=[L]; continue
        if name is not None:
            buf.append(L)
            if L.rstrip()=='};':
                if name not in d: d[name]=''.join(buf)
                name=None; buf=[]
    return d
a=blocks('/home/builder/abi/full/opt12.txt'); b=blocks('/home/builder/abi/full/opt13.txt')
print("opt12 类型块=%d opt13 类型块=%d"%(len(a),len(b)))
diff=[k for k in set(a)|set(b) if a.get(k)!=b.get(k)]
print(">>> 内容真不同的类型 = %d"%len(diff))
for k in sorted(diff):
    sa=re.search(r'/\* size: (\d+)',a.get(k,'')); sb=re.search(r'/\* size: (\d+)',b.get(k,''))
    print("   %-30s size %s -> %s"%(k, sa.group(1) if sa else '无', sb.group(1) if sb else '无'))
PY
