set -u
SYM=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/out/vmlinux.symvers
echo "########## 负对照（应仍 PASS）##########"
python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt45.xml /home/builder/abi-opt47.xml $SYM 2>&1 | tail -6
echo
echo "########## 正对照（半径应显著变大）##########"
time python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt45.xml /home/builder/abi-opt46.xml $SYM 2>&1 | tail -14
