#!/bin/bash
# verify_image.sh —— GT5 Pro 自编内核刷前闸门套件（opt5..opt7 的血换成的一张表）
# 用法: bash verify_image.sh <裸Image 或 repacked.img> [基线目录, 默认 ~/opt5-baseline] [显示名]
# ⚠️ 本套件的边界（2026-09-29 实证）：**全绿 ≠ 能开机**。opt6 / -a / -a2 三个版本这套闸门全绿，刷进去全部循环开机。
#    它只能挡住"构建/配置/内容层"的错；运行时正确性只认刷机。
set -u
IMG_IN="${1:?用法: verify_image.sh <镜像路径> [基线目录] [显示名]}"
BASE="${2:-$HOME/opt5-baseline}"
NAME="${3:-$(basename "$IMG_IN")}"
TREE="${TREE:-$HOME/kwork/cctv18/repo/local/kernel_workspace/common}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; NA=0
line() { printf "  %-4s %-34s %s\n" "$1" "$2" "$3"; }
ck() { # ck <PASS|FAIL|NA> <名字> <详情>
  case "$1" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; NA) NA=$((NA+1));; esac
  line "$1" "$2" "$3"
}

# ---------- 0) 取内核段 ----------
SZ=$(stat -c %s "$IMG_IN")
if [ "$SZ" -gt 100000000 ]; then
  python3 - "$IMG_IN" "$WORK/k.img" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
ks,=struct.unpack('<I', d[8:12])
assert d[4096:4098]==b'MZ', "boot v4 头 MZ 缺失"
open(sys.argv[2],'wb').write(d[4096:4096+ks])
print("   (识别为 repacked boot v4: kernel_size=%d, AVBf=%s)" % (ks, d[-64:-60]==b'AVBf'))
PY
else
  cp -f "$IMG_IN" "$WORK/k.img"
  echo "   (识别为裸 Image)"
fi
[[ -f "$WORK/k.img" ]] || { echo "取内核段失败"; exit 2; }

# ---------- 1) ikconfig 双口径 ----------
if [ -x "$TREE/scripts/extract-ikconfig" ]; then
  ( cd "$TREE" && ./scripts/extract-ikconfig "$WORK/k.img" ) > "$WORK/ic.txt" 2>/dev/null
fi
[ -s "$WORK/ic.txt" ] || { echo "   ikconfig 抽取失败(内核没开 IKCONFIG?)"; : > "$WORK/ic.txt"; }

SUF=$(strings "$WORK/k.img" | grep -m1 -oE '6\.1\.141-android14-11-o-ltcdz5[a-z0-9-]*' || true)
[ -n "$SUF" ] && ck PASS "版本后缀可辨识" "$SUF" || ck FAIL "版本后缀可辨识" "取不到(每版必须改 setlocalversion)"
grep -q "clang version 17.0.2" "$WORK/ic.txt" && ck PASS "编译器 AOSP clang" "17.0.2" \
  || ck FAIL "编译器 AOSP clang" "$(grep -m1 CC_VERSION_TEXT "$WORK/ic.txt" | cut -c1-60)"

for k in DEFAULT_BBR DEFAULT_FQ TCP_CONG_BRUTAL NET_SCH_CAKE BBG LZ4_COMPRESS EROFS_FS_ZIP NET_SCH_DEFAULT; do
  grep -q "^CONFIG_$k=y" "$WORK/ic.txt" && ck PASS "特性在 $k" "=y" || ck FAIL "特性在 $k" "缺"
done
grep -q '^CONFIG_DEFAULT_TCP_CONG="bbr"' "$WORK/ic.txt" && ck PASS "默认拥塞=bbr" "" || ck FAIL "默认拥塞=bbr" ""
grep -q '^CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"' "$WORK/ic.txt" \
  && ck PASS "regdb 内嵌声明" "" || ck FAIL "regdb 内嵌声明" "缺"

# ---------- 2) 不该有的东西 ----------
grep -qE '^CONFIG_KSU' "$WORK/ic.txt" && ck FAIL "无内置 KSU(LKM 路线)" "发现了 CONFIG_KSU" || ck PASS "无内置 KSU(LKM 路线)" "0 行"
N=$(strings "$WORK/k.img" | grep -ci susfs); [ "$N" = 0 ] && ck PASS "无 SUSFS" "字符串 0" || ck FAIL "无 SUSFS" "命中 $N"
for k in OPLUS_FEATURE_EAS_OPT OPLUS_FEATURE_TASK_CPUSTATS; do
  grep -q "^CONFIG_$k=y" "$WORK/ic.txt" && ck FAIL "死开关未混入 $k" "居然 =y" || ck PASS "死开关未混入 $k" "not set"
done

# ---------- 3) regdb 真内嵌(整文件字节, 不是同名字符串) ----------
for f in regulatory.db regulatory.db.p7s; do
  src=""; for c in "$TREE/firmware/$f" "$BASE/$f"; do [ -f "$c" ] && src="$c" && break; done
  if [ -z "$src" ]; then ck NA "regdb 字节指纹 $f" "找不到原件"; continue; fi
  n=$(python3 -c "import sys;print(open(sys.argv[1],'rb').read().count(open(sys.argv[2],'rb').read()))" "$WORK/k.img" "$src")
  [ "$n" -ge 1 ] && ck PASS "regdb 字节指纹 $f" "整文件命中 $n" || ck FAIL "regdb 字节指纹 $f" "0 次(没内嵌)"
done

# ---------- 4) IP6_NF_NAT 双口径(挡住 config_fix 谎报) ----------
A=$(grep -oE '^CONFIG_IP6_NF_NAT=[a-z]' "$WORK/ic.txt" | tail -1 | cut -d= -f2)
B=""; [ -f "$TREE/out/include/config/auto.conf" ] && B=$(grep -oE 'CONFIG_IP6_NF_NAT=[a-z]' "$TREE/out/include/config/auto.conf" | cut -d= -f2)
FIX=$(grep -c config_fix "$TREE/kernel/Makefile" 2>/dev/null); FIX=${FIX:-0}
if [ "${A:-}" = "y" ]; then ck PASS "IP6_NF_NAT 内嵌值" "=y(config_fix 计数 $FIX)"
elif [ -n "$B" ] && [ "$B" = "y" ]; then ck FAIL "IP6_NF_NAT 内嵌值" "auto.conf=y 但内嵌=$A ⇒ 这份镜像构建时被 config_fix 谎报了(当前树 config_fix=$FIX)"
else ck FAIL "IP6_NF_NAT 内嵌值" "=$A"; fi

# ---------- 5) 与上一版对照(有基线才算) ----------
if [ -f "$BASE/System.map" ] && [ -f "$TREE/out/System.map" ]; then
  a=$(wc -l < "$BASE/System.map"); b=$(wc -l < "$TREE/out/System.map")
  [ "$a" = "$b" ] && ck PASS "System.map 行数 = 基线" "$a" || ck NA "System.map 行数 vs 基线" "基线 $a / 当前 $b(不同构建路径可解释)"
fi
if [ -f "$BASE/Module.symvers" ] && [ -f "$TREE/out/Module.symvers" ]; then
  python3 - "$BASE/Module.symvers" "$TREE/out/Module.symvers" <<'PY' | sed 's/^/  /'
import sys
def load(p): return {l.split('\t')[1]: l.split('\t')[0] for l in open(p) if '\t' in l}
a,b=load(sys.argv[1]),load(sys.argv[2])
ch=len([k for k in set(a)&set(b) if a[k]!=b[k]]); rm=len(set(a)-set(b)); ad=len(set(b)-set(a))
print(("PASS" if ch==0 and rm==0 else "FAIL"), "symvers CRC 对照基线", "变 %d / 消 %d / 记账多 %d" % (ch,rm,ad))
print("     (注: '多/少'只作线索不作证据 —— 2026-09-29 实证 symvers 口径会随 make all / make Image 不同)")
PY
  FAIL=$((FAIL)) # 上面已自行判定, 这里不重复计数
fi
DF="$TREE/arch/arm64/configs/gki_defconfig"
if [ -f "$DF" ]; then
  d=$(grep '^CONFIG_' "$DF" | sed 's/=.*//' | sort | uniq -d | wc -l); l=$(wc -l < "$DF")
  [ "$d" = 0 ] && ck PASS "gki_defconfig 无重复键" "$l 行 / 重复 0" || ck FAIL "gki_defconfig 无重复键" "$l 行 / 重复 $d"
fi

echo
echo "===== $NAME : PASS=$PASS  FAIL=$FAIL  NA=$NA ====="
[ "$FAIL" = 0 ] || echo "  ⚠️ 有 FAIL 项就先别刷。全绿也只是'构建与内容层没问题'——不代表能开机。"
exit $((FAIL>0))
