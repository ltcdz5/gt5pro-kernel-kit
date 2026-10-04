#!/bin/bash
# opt7-clean 刷前闸门: 重点是 "/proc/config.gz 不再撒谎" 这一条必须反转
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
IMG=out/arch/arm64/boot/Image
echo "=== 0) 产物新鲜度 ==="
date "+现在 %H:%M:%S"; ls -la "$IMG"
echo
echo "=== 1) 版本后缀 / 编译器 ==="
strings "$IMG" | grep -m1 'Linux version' | cut -c1-58
grep CC_VERSION_TEXT out/.config | cut -c1-72
echo
echo "=== 2) ⭐ 谎报已消失: Image 内嵌 config 必须报 IP6_NF_NAT=y ==="
./scripts/extract-ikconfig "$IMG" > /tmp/ic7.txt
grep -E "CONFIG_IP6_NF_NAT" /tmp/ic7.txt
echo "   kernel/Makefile 里 config_fix 残留: $(grep -c config_fix kernel/Makefile)"
echo
echo "=== 3) 生效配置与 opt5 逐行一致(期望 0) ==="
echo "   差异行数: $(diff <(sort "$BASE/config") <(sort out/.config) | grep -cE '^[<>]')"
diff <(sort "$BASE/config") <(sort out/.config) | grep -E "^[<>]" | head -6
echo
echo "=== 4) defconfig 本身干不干净 ==="
F=arch/arm64/configs/gki_defconfig
echo "   行数 $(wc -l < $F)  重复键 $(grep '^CONFIG_' $F | sed 's/=.*//' | sort | uniq -d | wc -l)  工作区未跟踪垃圾 $(git status --porcelain | grep -c '^??')"
echo
echo "=== 5) 我们的特性逐项 ==="
grep -E "^CONFIG_(DEFAULT_BBR|DEFAULT_TCP_CONG|DEFAULT_FQ|NET_SCH_DEFAULT|TCP_CONG_BRUTAL|NET_SCH_CAKE|EXTRA_FIRMWARE|EXTRA_FIRMWARE_DIR|BBG|LZ4_COMPRESS|EROFS_FS_ZIP)\b" /tmp/ic7.txt | sort
echo "   死开关 not set: $(grep -cE 'CONFIG_OPLUS_FEATURE_(EAS_OPT|TASK_CPUSTATS) is not set' /tmp/ic7.txt)/2   内置 KSU: $(grep -cE '^CONFIG_KSU' /tmp/ic7.txt)   SUSFS 字符串: $(strings "$IMG" | grep -ci susfs)"
echo
echo "=== 6) regdb 整文件字节指纹(在最终 Image) ==="
python3 - "$IMG" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
for f in ("regulatory.db","regulatory.db.p7s"):
    b=open("firmware/"+f,'rb').read()
    print("   %-20s %5dB 完整命中 %d 次" % (f, len(b), d.count(b)))
PY
echo
echo "=== 7) KMI: 与 opt5 基线逐符号比 CRC ==="
python3 - "$BASE/Module.symvers" out/Module.symvers <<'PY'
import sys
def load(p): return {l.split('\t')[1]: l.split('\t')[0] for l in open(p) if '\t' in l}
a,b=load(sys.argv[1]),load(sys.argv[2])
print("   opt5=%d opt7=%d | CRC 变 %d | 消失 %d | 新增 %d" % (len(a),len(b),
      len([k for k in set(a)&set(b) if a[k]!=b[k]]), len(set(a)-set(b)), len(set(b)-set(a))))
PY
echo
echo "=== 8) 与 opt5 的 Image 逐字节差异面积(应极小, 只差 banner/时间戳) ==="
python3 - <<PY
a=open("$BASE/Image.opt5",'rb').read(); b=open("$IMG",'rb').read()
n=min(len(a),len(b)); diff=sum(1 for i in range(0,n,1) if a[i]!=b[i])
print("   大小 %s vs %s ; 不同的字节数 %d (%.4f%%)" % (len(a), len(b), diff, 100.0*diff/n))
PY
cp -f "$IMG" /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核/boot-opt7-clean.raw.img
md5sum "$IMG"
