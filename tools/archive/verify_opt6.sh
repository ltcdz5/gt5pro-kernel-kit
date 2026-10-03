#!/bin/bash
# opt6 刷前三重验证: 编译器 / 配置落地 / regdb 内嵌 / KMI 符号 CRC 对照 opt5 基线
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
IMG=$TREE/out/arch/arm64/boot/Image
cd "$TREE" || exit 1
echo "=== 0) 产物时间戳(必须晚于本轮启动) ==="
date "+现在 %H:%M:%S"; ls -la "$IMG"
echo
echo "=== 1) 编译器必须是 AOSP clang 17.0.2 ==="
grep CC_VERSION_TEXT out/.config
echo
echo "=== 2) 版本后缀真的进了 Image ==="
strings "$IMG" 2>/dev/null | grep -m2 "6\.1\.141-android14" || grep -a -o "6\.1\.141-android14[^ ]*" "$IMG" | head -2
echo
echo "=== 3) 我们的配置项 + BRUTAL 有没有被上游改动弄丢 ==="
./scripts/extract-ikconfig "$IMG" > /tmp/ic6.txt 2>/dev/null || zcat out/.config > /tmp/ic6.txt
grep -E "CONFIG_(DEFAULT_BBR|DEFAULT_TCP_CONG|NET_SCH_DEFAULT|DEFAULT_FQ|DEFAULT_FQ_CODEL|TCP_CONG_BRUTAL|TCP_CONG_ADVANCED|NET_SCH_CAKE|EXTRA_FIRMWARE|EXTRA_FIRMWARE_DIR|KSU|EROFS_FS_ZIP|LZ4_COMPRESS|F2FS_FS)\b|CONFIG_TCP_CONG_BBR|CONFIG_LOCALVERSION" /tmp/ic6.txt | sort
echo "  --- 死开关应为 not set ---"
grep -E "CONFIG_OPLUS_FEATURE_(EAS_OPT|TASK_CPUSTATS|LOADBALANCE|SCHED_SPREAD|GKI_CPUFREQ_BOUNCING|POWER_DIAG|SUGOV_POWER_EFFIENCY)\b" /tmp/ic6.txt
echo
echo "=== 4) regdb 内嵌字节指纹(用文件真实字节搜 Image, 不是搜同名字符串) ==="
python3 - "$IMG" <<'PY'
import sys
img=open(sys.argv[1],'rb').read()
for f in ('firmware/regulatory.db','firmware/regulatory.db.p7s'):
    b=open(f,'rb').read()
    print(f"  {f:28} {len(b)}B 头4字节={b[:4]!r} Image 内命中 {img.count(b)} 次")
PY
echo
echo "=== 5) KMI 硬闸: Module.symvers 逐符号 CRC 与 opt5 基线对比 ==="
if [ -f "$BASE/Module.symvers" ] && [ -f out/Module.symvers ]; then
  python3 - "$BASE/Module.symvers" out/Module.symvers <<'PY'
import sys
def load(p):
    d={}
    for L in open(p):
        t=L.rstrip('\n').split('\t')
        if len(t)>=2: d[t[1]]=(t[0], t[2] if len(t)>2 else '', t[3] if len(t)>3 else '')
    return d
a,b=load(sys.argv[1]),load(sys.argv[2])
chg=[k for k in set(a)&set(b) if a[k][0]!=b[k][0]]
rem=sorted(set(a)-set(b)); add=sorted(set(b)-set(a))
print(f"  符号数 opt5={len(a)}  opt6={len(b)}")
print(f"  CRC 变化的符号: {len(chg)}   (0 = 厂商 .ko 的 CRC 校验不受影响)")
for k in sorted(chg)[:25]: print(f"    ~ {k}: {a[k][0]} -> {b[k][0]}")
print(f"  opt5 有而 opt6 没有(最危险): {len(rem)}")
for k in rem[:25]: print(f"    - {k}")
print(f"  新增符号: {len(add)} (示例 {', '.join(add[:6])})")
PY
else
  echo "  ! 缺 Module.symvers, 无法对比"
fi
echo "=== 验证结束 ==="
