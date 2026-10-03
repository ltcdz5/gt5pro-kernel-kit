#!/system/bin/sh
# 唯一动作：在厂商那次开机清零之后，把 lru_gen 的两项运行时值恢复成 Y / 1000。
# 纪律：无 while true 常驻轮询；等 boot_completed（上限 60x2 秒）后再等 15 秒写一次，写完退出。
# 边界：只写这两个 sysfs 节点。不 resetprop、不 bind mount、不注入、不碰 SELinux、不碰其它厂商内存参数。
D=/data/adb/lru_gen_on
LOG=$D/state.log
NODE=/sys/kernel/mm/lru_gen/enabled
TTL=/sys/kernel/mm/lru_gen/min_ttl_ms

mkdir -p "$D" 2>/dev/null
chmod 700 "$D" 2>/dev/null

i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i+1))
done
sleep 15

BEFORE=$(cat "$NODE" 2>/dev/null)
echo Y > "$NODE" 2>/dev/null
echo 1000 > "$TTL" 2>/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') stage=service before=$BEFORE wrote=Y enabled=$(cat "$NODE" 2>/dev/null) min_ttl=$(cat "$TTL" 2>/dev/null)" >> "$LOG" 2>/dev/null
chmod 600 "$LOG" 2>/dev/null
