#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_commit_and_repack.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
OUT=/home/builder/opt10probe
IMG=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
echo "=== 1) 提交 opt10 源码状态(只提交已跟踪文件, 防卷入未跟踪残留) ==="
echo "  未跟踪文件数=$(git status --porcelain | grep -c '^??')"
git status --porcelain | grep '^??' | head -5 | sed 's/^/    忽略: /'
git commit -q -a -F - <<'MSG'
opt10 = opt9 + stable 6.1.142..145 中自洽落地的 10 个纯 .c 修复 + 后缀 -opt10

落地面: block/blk-mq-debugfs.c fs/filesystems.c kernel/power/wakelock.c
        mm/hugetlb_cgroup.c net/core/gen_estimator.c net/ipv6/ila/ila_common.c
        net/ipv6/ipv6_sockglue.c net/ipv6/netfilter.c net/sched/sch_prio.c
        security/selinux/xfrm.c
退回原因: 头文件/.S/dts/Kconfig 类改动 92 个 —— stable 的 .c 假设上游头,
          我们的头被 Oplus 改过, 逐文件套会造成 141 个编译错(cred.c/rtmutex.c/
          posix-timers.c 等 "结构体成员不存在")。只保留不需要头变更的那批。
实测闸: 新增导出 0 / 命中厂商 .ko 引用 0; config 与 opt9 差 0 行;
        全类型 BTF 与 opt9 差 0 行(sk_buff 192->216 是 opt9 自带的, 非本版引入)。
MSG
echo "  $(git log --oneline -1)"
echo "  脏=$(git status --porcelain | wc -l)"
SHA=$(git rev-parse --short HEAD)

echo "=== 2) repack ==="
cp -f "$OUT/Image.opt10" /tmp/Image.opt10
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /tmp/Image.opt10 "$IMG/boot-opt10-repacked.img" 2>&1 | tail -6
md5sum "$IMG/boot-opt10-repacked.img"
ls -l "$IMG/boot-opt10-repacked.img" | sed 's/^/  /'
echo "  提交=$SHA  分支=$(git rev-parse --abbrev-ref HEAD)"
