#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/map_drift.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 用 System.map 的地址排布量"头文件 include 图改动"的全局扰动。
# 同配置、同编译器、同基线源码 —— 地址漂动的符号数就是 codegen 扰动的读数。
BASE=/home/builder/opt5-baseline
python3 - <<'PY'
def load(p):
    m={}
    for L in open(p, errors='replace'):
        f=L.split()
        if len(f)==3:
            try: m[f[2]]=(int(f[0],16), f[1])
            except ValueError: pass
    return m
b=load('/home/builder/opt5-baseline/System.map')
print("opt5 符号数=%d" % len(b))
for tag,p in [('a4(blk-mq 一对)','/home/builder/a4probe/System.map.a4'),
              ('a5(只 file.h)','/home/builder/a5probe/System.map.a5')]:
    try:
        c=load(p)
    except FileNotFoundError:
        print("  %s: System.map 还没生成" % tag); continue
    same = set(b) & set(c)
    drift = [k for k in same if b[k][0]!=c[k][0]]
    gone  = sorted(set(b)-set(c)); new = sorted(set(c)-set(b))
    print("\n%s: 符号数=%d  共同=%d  地址漂移=%d(%.2f%%)  消失=%d  新增=%d"
          % (tag, len(c), len(same), len(drift), 100.0*len(drift)/max(1,len(same)), len(gone), len(new)))
    if drift:
        mx=max(abs(c[k][0]-b[k][0]) for k in drift)
        print("     最大地址位移=%d 字节(%.1fKB)" % (mx, mx/1024.0))
        print("     漂移符号样例:", ", ".join(drift[:6]))
    for k in new[:8]: print("     +", k, c[k])
    for k in gone[:8]: print("     -", k)
PY
echo
echo '=== 三份 Image 的体积/指纹(同基线, 体积差就是净增代码量) ==='
for f in /home/builder/opt5-baseline/Image.opt5 /home/builder/a4probe/Image.a4 /home/builder/a5probe/Image.a5; do
  [ -f "$f" ] && printf '  %-42s %10d  %s\n' "$(basename $f)" "$(stat -c%s $f)" "$(md5sum $f | cut -c1-10)"
done
echo
echo '=== 头文件改动前后: include 图到底多拉了什么(file.h) ==='
grep -n '#include' /home/builder/kwork/cctv18/repo/local/kernel_workspace/common/include/linux/file.h 2>/dev/null | head -8 | sed 's/^/  /'
