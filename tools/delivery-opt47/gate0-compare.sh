set -u
SYM=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/out/vmlinux.symvers
echo "########## 负对照：opt45 -> opt47（只改了 i2c 函数体，应 PASS）##########"
python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt45.xml /home/builder/abi-opt47.xml $SYM 2>&1 | tail -14
echo "rc=$?"
echo
echo "########## 正对照：opt45 -> opt46（BBRv3，闸门2 曾报 367/493，应 FAIL 并点名类型）##########"
time python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt45.xml /home/builder/abi-opt46.xml $SYM 2>&1 | head -42
