#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/ruler_sample.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
OUT=/data/local/tmp/boot_ruler.tsv
TAG="$1"
[ -f "$OUT" ] || echo -e "round\tboot_ms\tzygote_ms\tkcode_kB" > "$OUT"

w=0
while [ $w -lt 180 ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
  sleep 1; w=$((w+1))
done
sleep 3

UPM=$(cut -d' ' -f1 /proc/uptime | awk '{printf "%d", $1*1000}')

Z=$(dmesg 2>/dev/null | grep -m1 -E 'zygote' | sed -E 's/^\[ *([0-9]+)\.([0-9]+)\].*/\1 \2/')
if [ -n "$Z" ]; then ZS=${Z% *}; ZU=${Z#* }; ZMS=$(( ZS*1000 + ZU/1000 )); else ZMS=NA; fi

# 从 Memory: 行里抠出 "17664K kernel code" 的数字
LINE=$(dmesg 2>/dev/null | grep -m1 'Memory:')
KC=$(echo "$LINE" | grep -oE '[0-9]+K kernel code' | grep -oE '^[0-9]+')

echo -e "$TAG\t$UPM\t$ZMS\t${KC:-NA}" >> "$OUT"
echo "第 $TAG 轮: boot=${UPM}ms zygote=${ZMS}ms kcode=${KC}KB"
