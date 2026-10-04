set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
K=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit
echo "=== 闸门1 ==="
python3 $K/tools/gate_new_exports.py out/vmlinux.symvers 2>&1 | tail -5
echo
echo "=== 闸门2 ==="
python3 $K/tools/gate_vko_crc.py out/vmlinux.symvers \
  /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm \
  /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/system_dlkm 2>&1 > /tmp/g2o47.txt
grep -E "会拒绝装载的模块|合计涉及" /tmp/g2o47.txt
echo "--- 若 >1，列出不是蓝牙的 ---"
grep -B1 "个符号不符" /tmp/g2o47.txt | grep -v "bluetooth" | head -10
