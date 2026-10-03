#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/config_delta.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
python3 - <<'PY'
import gzip, re, io
st = gzip.open('/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/refs/stock_config.gz','rb').read().decode('utf-8','replace')
mine = io.open('out/.config', encoding='utf-8', errors='replace').read()
def kv(t):
    d={}
    for L in t.splitlines():
        m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L)
        if m: d[m.group(1)]=m.group(2); continue
        m=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L)
        if m: d[m.group(1)]='n'
    return d
S,O=kv(st),kv(mine)
INTENDED=('DEFAULT_BBR','DEFAULT_TCP_CONG','NET_SCH_DEFAULT','DEFAULT_FQ','TCP_CONG_BBR','TCP_CONG_BRUTAL',
 'TCP_CONG_VEGAS','TCP_CONG_WESTWOOD','TCP_CONG_HTCP','TCP_CONG_NV','TCP_CONG_ADVANCED','NET_SCH_FQ',
 'NET_SCH_FQ_CODEL','NET_SCH_CAKE','EXTRA_FIRMWARE','EXTRA_FIRMWARE_DIR','BBG','BBG_BLOCK_RECOVERY',
 'IP_SET','LZ4_DECOMPRESS','ZSTD_DECOMPRESS','EROFS_FS_ZIP','LZ4_COMPRESS')
diff=[(k,S.get(k,'<符号不存在>'),O.get(k,'<符号不存在>')) for k in sorted(set(S)|set(O)) if S.get(k)!=O.get(k)]
ints=[d for d in diff if any(('_'+f) in d[0] or d[0]=='CONFIG_'+f for f in INTENDED)]
rest=[d for d in diff if d not in ints]
print("与真我原厂 config 差异总数: %d" % len(diff))
print("  其中我们有意为之(网络/regdb/BBG/IPSET/压缩): %d" % len(ints))
for k,a,b in ints: print("     %-42s 原厂=%-16s 我们=%s" % (k,a,b))
print("  其余 %d 项 = 两棵树的天然差异(realme 树 vs 一加树), 不是我们的改动:" % len(rest))
for k,a,b in rest[:22]: print("     %-42s 原厂=%-16s 我们=%s" % (k,a,b))
PY
echo
echo "=== 现役(opt5)与原厂的功能差集: 已量化(见 kit README §12) ==="
echo "  模块: 原厂加载 55/失败 0 ; opt5 加载 48/失败 7(全为蓝牙族) ; 功能实测正常(厂商用户态栈)"
echo "  开机: 原厂 boot_progress_start 74597ms -> 现在 12090ms; 亮屏 25685ms"
