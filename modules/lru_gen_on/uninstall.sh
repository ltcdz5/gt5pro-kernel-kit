#!/system/bin/sh
# 卸载＝把本模块改过的两项回到本机开机原生值，并清掉它自己产生的文件。
#   enabled      -> n（本机开机后原生就是 0x0000）
#   min_ttl_ms   -> 0（本机原生 0）
# 文件：私有目录 /data/adb/lru_gen_on（v3 起）与旧版残留 /data/adb/lru_gen_on.log（v2 及更早）
echo 0 > /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null
echo n > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
rm -rf /data/adb/lru_gen_on
rm -f /data/adb/lru_gen_on.log
exit 0
