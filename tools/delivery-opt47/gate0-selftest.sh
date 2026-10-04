set -u
cd /home/builder 2>/dev/null
echo "=== 自比对（ref == cand，应报零变化）==="
time python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt47.xml /home/builder/abi-opt47.xml 2>&1 | tail -12
echo
echo "=== 带导出集的自比对（应报 0）==="
python3 /mnt/f/工作区/gate0_type_diff.py /home/builder/abi-opt47.xml /home/builder/abi-opt47.xml /home/builder/kwork/cctv18/repo/local/kernel_workspace/common/out/vmlinux.symvers 2>&1 | tail -6
