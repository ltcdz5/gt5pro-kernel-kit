set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git checkout -q -B opt47 opt45 && echo '已切到 opt47（基于 opt45）'
python3 /mnt/f/工作区/patch-opt47.py
echo
echo '=== 改动汇总 ==='
git diff --stat
echo
echo '=== diff 全文 ==='
git diff