#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get install -y qemu-system-arm qemu-user-static 2>&1 | tail -6
echo "=== qemu 版本 ==="
qemu-system-aarch64 --version 2>&1 | head -2
echo "=== 机器类型里有 virt 吗 ==="
qemu-system-aarch64 -machine help 2>/dev/null | grep -E '^virt|^xlnx-zebu|^sbsa' | head -6
