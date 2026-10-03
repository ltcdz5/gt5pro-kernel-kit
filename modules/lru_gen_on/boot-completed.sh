#!/system/bin/sh
# 第三个读数点：boot_completed 触发瞬间，只读不写。
# 配合 service.sh 里的 before= 值，能判断清零发生在"开机完成之前"还是"之后"。
D=/data/adb/lru_gen_on
LOG=$D/state.log
mkdir -p "$D" 2>/dev/null
chmod 700 "$D" 2>/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') stage=boot-completed enabled=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null)" >> "$LOG" 2>/dev/null
chmod 600 "$LOG" 2>/dev/null
