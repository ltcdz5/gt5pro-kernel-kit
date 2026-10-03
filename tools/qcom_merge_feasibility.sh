#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/qcom_merge_feasibility.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 量两件事 —— (1) 高通代码在我们产物里是 =y 还是 =m(=m 的改了也进不了刷的 boot)
#                  (2) stable 142~145 里高通/驱动侧文件有多少能干净落地
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/patches/stable
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

echo "=== (1) 高通相关配置在本机构建里的形态 ==="
python3 - <<'PY'
import io,re,collections
cur={}
for L in io.open('/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/out/.config',encoding='utf-8',errors='replace'):
    m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(y|m|n)?(.*)',L.strip())
    if m: cur[m.group(1)]=m.group(2) or ('=""+' )
    else:
        m=re.match(r'#\s*(CONFIG_\w+)\s+is not set',L.strip())
        if m: cur[m.group(1)]='n'
q={k:v for k,v in cur.items() if re.search(r'QCOM|MSM_|UFS_QCOM|ADRENO|IPA_|RMNET|GENI_|ICCCOMM|QTI_|SPSS|MEMSHARED',k)}
c=collections.Counter(q.values())
print("  高通相关配置项总数 = %d" % len(q))
for k,v in sorted(c.items(), key=lambda x:-x[1]): print("    %-6s %d 项" % (k if k!='="\"' else '有值', v))
print("\n  其中 =y(内建, 我们改得动) 的:")
for k,v in sorted(q.items()):
    if v=='y': print("    ",k)
print("\n  =m(模块化, 刷机不带走, 改了无效) 的样例前 12:")
n=0
for k,v in sorted(q.items()):
    if v=='m' and n<12: print("    ",k); n+=1
PY

echo
echo "=== (2) stable 142~145 里"驱动侧"文件的可落地率 ==="
for v in 142 143 144 145; do
  xz -dc "$P/patch-6.1.$v.xz" > /tmp/drv$v 2>/dev/null
  python3 - "$v" /tmp/drv$v <<'PY'
import sys, re, subprocess, os, collections
v, f = sys.argv[1], sys.argv[2]
blocks, cur, name = [], None, None
for L in open(f, errors='replace'):
    m = re.match(r'^diff --git a/(\S+)', L)
    if m:
        if cur is not None: blocks.append((name, cur))
        name, cur = m.group(1), [L]
    elif cur is not None: cur.append(L)
if cur is not None: blocks.append((name, cur))
QCOM = re.compile(r'^(drivers/(soc/qcom|gpu/drm/msm|ufs|remoteproc|firmware|iommu/qcom|interconnect|pinctrl/qcom|clk/qcom|phy/qcom|usb/dwc3|npu|crypto/qcom|input|leds|power)|arch/arm64)/')
qs = [(f_,b) for f_,b in blocks if f_ and QCOM.match(f_)]
clean = rej = 0
rejnames=[]
os.makedirs('/tmp/drvsplit', exist_ok=True)
for i,(fn,b) in enumerate(qs):
    p='/tmp/drvsplit/%s_%d.diff'%(v,i)
    open(p,'w').write(''.join(b))
    r=subprocess.run(['git','apply','--check','--whitespace=nowarn',p],capture_output=True,text=True,cwd=os.getcwd())
    if r.returncode==0: clean+=1
    else: rej+=1; rejnames.append(fn)
print("  %s: 驱动/平台侧文件=%-4d 能干净落地=%-3d 冲突=%-3d 落地率=%s%%" % (
    v, len(qs), clean, rej, (0 if not qs else round(clean*100/len(qs)))))
if v=='142':
    print("     (冲突样例前 6:)")
    for x in rejnames[:6]: print("       ", x)
PY
done
