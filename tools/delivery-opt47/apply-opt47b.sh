set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
python3 /mnt/f/工作区/patch-opt47b.py
echo
echo '=== 改动汇总 ==='
git diff --stat
echo
echo '=== 完整 diff ==='
git diff drivers/i2c/i2c-core-base.c