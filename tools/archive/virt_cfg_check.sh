#!/bin/bash
BASE=/home/builder/opt5-baseline
CFG=$BASE/config
echo "=== 现役 opt5 配置里 qemu-virt 相关的项 ==="
for k in CONFIG_ARCH_VIRT CONFIG_VIRTIO CONFIG_VIRTIO_MENU CONFIG_VIRTIO_BLK CONFIG_VIRTIO_PCI \
         CONFIG_SERIAL_AMBA_PL011 CONFIG_SERIAL_AMBA_PL011_CONSOLE CONFIG_ARM_AMBA \
         CONFIG_BLK_DEV_INITRD CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT CONFIG_SYSFS CONFIG_PROC_FS \
         CONFIG_PSTORE CONFIG_PSTORE_RAM CONFIG_EARLY_PRINTK CONFIG_ARM64_PA_BITS \
         CONFIG_PCI CONFIG_OF CONFIG_CGROUPS CONFIG_MULTIUSER; do
  printf '%-34s %s\n' "$k" "$(grep -m1 "^$k=" $CFG || echo 'MISSING')"
done
echo
echo "=== 本地能拿来喂 QEMU 的裸内核 Image ==="
ls -l /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核/ 2>/dev/null
echo "--- out/ 里现在这份是谁 ---"
md5sum /home/builder/kwork/cctv18/repo/local/kernel_workspace/common/out/arch/arm64/boot/Image 2>/dev/null
ls -l /home/builder/opt5-baseline/
