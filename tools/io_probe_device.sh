#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/io_probe_device.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 量 I/O 侧能做多少 —— 设备侧旋钮的可写性与当前值
ADB="D:/gaojizhushou/adb.exe"
echo "=== A. 块队列旋钮: 权限位 + 当前值 (sda=UFS 整盘) ==="
$ADB shell "su -c 'for k in scheduler nr_requests read_ahead_kb rq_affinity add_random rotational logical_block_size nr_hw_queues; do f=/sys/block/sda/queue/\$k; if [ -e \$f ]; then printf \"  %-20s %-10s %s\n\" \$k \"\$(ls -l \$f | cut -c2-10)\" \"\$(cat \$f | head -1)\"; else printf \"  %-20s 无此节点\n\" \$k; fi; done'" 2>&1 | tr -d '\r'
echo
echo "=== B. UFS 主机侧(厂商 .ko 管的, 我们改不到?) ==="
$ADB shell "su -c 'for f in /sys/devices/platform/1d84000.ufshc/clkscale_enable /sys/devices/platform/1d84000.ufshc/hpb_enabled /sys/devices/platform/1d84000.ufshc/auto_hibern8; do [ -e \$f ] && printf \"  %-22s %-10s %s\n\" \$(basename \$f) \"\$(ls -l \$f|cut -c2-10)\" \"\$(cat \$f)\" || printf \"  %-22s 无\n\" \$(basename \$f); done'" 2>&1 | tr -d '\r'
echo
echo "=== C. f2fs 可调项(取一个挂载实例) ==="
$ADB shell "su -c 'ls -d /sys/fs/f2fs/* 2>/dev/null; echo ---; ls -l /sys/fs/f2fs/ 2>/dev/null | head -3'" 2>&1 | tr -d '\r'
D=$($ADB shell "su -c 'ls -d /sys/fs/f2fs/* 2>/dev/null | head -1'" | tr -d '\r')
echo "  实例=$D 的节点(权限在前 10 列):"
$ADB shell "su -c 'ls -l $D 2>/dev/null | tail -22'" 2>&1 | tr -d '\r' | awk 'NR>1{printf "    %-11s %s\n", $1, $9}'
