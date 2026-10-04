#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
IC=$BASE/ic6.txt
./scripts/extract-ikconfig out/arch/arm64/boot/Image > "$IC"
echo "=== A) 版本串真的进了 Image ==="
strings out/arch/arm64/boot/Image | grep -m1 "Linux version"
echo
echo "=== B) Image 内嵌 config 与 opt5 基准的差异(期望 0) ==="
echo "  差异行数: $(diff "$BASE/config" "$IC" | grep -cE '^[<>]')"
diff "$BASE/config" "$IC" | grep -E "^[<>]" | head -10
echo
echo "=== C) 关键项回读 ==="
grep -E "^CONFIG_(DEFAULT_BBR|DEFAULT_TCP_CONG|DEFAULT_FQ|NET_SCH_DEFAULT|TCP_CONG_BRUTAL|TCP_CONG_CAKE|NET_SCH_CAKE|IP6_NF_NAT|EXTRA_FIRMWARE|EXTRA_FIRMWARE_DIR|EROFS_FS_ZIP|LZ4_COMPRESS|BBG|IP_SET)\b" "$IC" | sort
echo "  死开关(应 not set): $(grep -cE "CONFIG_OPLUS_FEATURE_(EAS_OPT|TASK_CPUSTATS) is not set" "$IC")/2"
echo "  内置 KSU 行数(应为 0): $(grep -cE '^CONFIG_KSU' "$IC")"
echo
echo "=== D) regdb 整文件字节指纹(在最终 Image 里) ==="
python3 - out/arch/arm64/boot/Image <<'PY'
import sys
img=open(sys.argv[1],'rb').read()
for f in ('firmware/regulatory.db','firmware/regulatory.db.p7s'):
    b=open(f,'rb').read()
    print(f"  {f:26} {len(b):5d}B  完整字节序列命中 {img.count(b)} 次")
PY
echo
echo "=== E) KMI 硬闸: 与 opt5 基线逐符号比 CRC ==="
python3 - "$BASE/Module.symvers" out/Module.symvers <<'PY'
import sys
def load(p):
    d={}
    for L in open(p):
        t=L.rstrip('\n').split('\t')
        if len(t)>=2: d[t[1]]=t[0]
    return d
a,b=load(sys.argv[1]),load(sys.argv[2])
chg=[k for k in set(a)&set(b) if a[k]!=b[k]]
print(f"  符号数 opt5={len(a)} opt6={len(b)} | CRC 变化 {len(chg)} | 消失 {len(set(a)-set(b))} | 新增 {len(set(b)-set(a))}")
for k in sorted(chg)[:20]: print(f"    ~ {k}")
for k in sorted(set(a)-set(b))[:20]: print(f"    - 消失: {k}")
PY
echo
echo "=== F) System.map 里上游新增的 hook 符号确实在 ==="
for s in android_vh_resched_curr_lazy android_vh_lock_task_fork android_vh_lock_task_exit; do
  printf "  %-34s %s\n" "$s" "$(grep -c "$s" out/System.map)"
done
cp -f out/arch/arm64/boot/Image /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt6-ltcdz5-up0914-raw.img
md5sum out/arch/arm64/boot/Image out/Module.symvers
