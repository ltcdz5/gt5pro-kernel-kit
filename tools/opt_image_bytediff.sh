#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_image_bytediff.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 退料前后镜像字节差在哪：只允许是 banner 的构建时间戳
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
A=/home/builder/opt-prune/Image.before
B=$T/out/arch/arm64/boot/Image
cd "$T" || exit 1
echo "size 前=$(stat -c%s "$A")  后=$(stat -c%s "$B")"
echo "差异字节数=$(cmp -l "$A" "$B" | wc -l)"
echo "首个差异偏移=$(cmp -l "$A" "$B" | head -1 | awk '{print $1}')"
strings -a "$A" > /tmp/a.s; strings -a "$B" > /tmp/b.s
echo "文本差异行数=$(diff /tmp/a.s /tmp/b.s | wc -l)"
echo "--- 文本差异内容 ---"
diff /tmp/a.s /tmp/b.s
