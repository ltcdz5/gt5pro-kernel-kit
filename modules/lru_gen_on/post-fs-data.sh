#!/system/bin/sh
# 阶段探针：post-fs-data 阶段只读一次 lru_gen 状态，不写任何节点。
# 用途：把"谁把 enabled 清成 0"框进 init 阶段之间。内核 late_initcall 之后 caps 应为 TRUE(0x0003)，
#      若这里就读到 0x0000，清零就发生在更早的用户态（init / vendor rc）。
D=/data/adb/lru_gen_on
LOG=$D/state.log
mkdir -p "$D" 2>/dev/null
chmod 700 "$D" 2>/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') stage=post-fs-data enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)" >> "$LOG" 2>/dev/null
chmod 600 "$LOG" 2>/dev/null
