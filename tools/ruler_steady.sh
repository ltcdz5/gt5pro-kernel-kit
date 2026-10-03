#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/ruler_steady.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 稳态探针: 开机后任何时候都能采, 不依赖 boot 时刻, 不依赖 dmesg 早期
# 用法: sh /data/local/tmp/ruler_steady.sh <秒数> <标签>
SECS=${1:-60}
TAG=${2:-x}
OUT=/data/local/tmp/steady_ruler.tsv
[ -f "$OUT" ] || echo -e "tag\tsecs\tpsi_cpu_us\tpsi_mem_us\tbusy_jiff\tidle_jiff" > "$OUT"

psi_cpu() { cat /proc/pressure/cpu 2>/dev/null | head -1 | sed -E 's/.*total=([0-9]+).*/\1/'; }
psi_mem() { cat /proc/pressure/memory 2>/dev/null | head -1 | sed -E 's/.*total=([0-9]+).*/\1/'; }
cpu_stat() { head -1 /proc/stat; }

echo "采样 ${SECS}s (标签=$TAG) ..."
C0=$(psi_cpu); M0=$(psi_mem); S0=$(cpu_stat)
sleep "$SECS"
C1=$(psi_cpu); M1=$(psi_mem); S1=$(cpu_stat)

# /proc/stat: user nice system idle iowait irq softirq steal
BUSY=$(echo "$S1" | awk '{print $2+$3+$4+$6+$7+$8}')
BUSY0=$(echo "$S0" | awk '{print $2+$3+$4+$6+$7+$8}')
IDLE=$(echo "$S1" | awk '{print $5}')
IDLE0=$(echo "$S0" | awk '{print $5}')
dBUSY=$((BUSY-BUSY0)); dIDLE=$((IDLE-IDLE0))
dPSIcpu=$(( ${C1:-0} - ${C0:-0} )); dPSImem=$(( ${M1:-0} - ${M0:-0} ))

echo -e "$TAG\t$SECS\t${C0:-0}\t${C1:-0}\t${M0:-0}\t${M1:-0}\t$dBUSY\t$dIDLE" >> "$OUT"
echo "[$TAG] ${SECS}s  dPSIcpu=${dPSIcpu}us dPSImem=${dPSImem}us  dBUSY=$dBUSY dIDLE=$dIDLE jiff  忙碌率=$(awk -v b=$dBUSY -v i=$dIDLE 'BEGIN{if(b+i>0) printf "%.1f%%", b*100/(b+i)}')"
