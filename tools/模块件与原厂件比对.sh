#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/模块件与原厂件比对.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 用只读挂载的真 vendor 分区(erofs)做对照，逐文件比模块件 —— 上一版读到了 overlay upper，作废重跑
M=/data/adb/modules/第三方 GPU 模块/system/vendor
T=/dev/tmpv
mkdir -p $T 2>/dev/null
mount -o ro /dev/block/dm-25 $T -t erofs 2>/dev/null || mount -o ro /dev/block/dm-25 $T 2>/dev/null
if [ ! -d "$T/lib64" ]; then echo "挂载失败，无法对照"; exit 1; fi
SAME=0; DIFF=0; MISS=0
for f in $(cd "$M" && find . -type f | sed 's|^\./||'); do
  if [ -e "$T/$f" ]; then
    s_size=$(stat -c %s "$T/$f"); s_md5=$(md5sum "$T/$f" | cut -c1-12); s_mt=$(stat -c %y "$T/$f" | cut -c1-19)
  else
    s_size=无; s_md5=-----------; s_mt=无
  fi
  m_size=$(stat -c %s "$M/$f"); m_md5=$(md5sum "$M/$f" | cut -c1-12)
  if [ "$s_md5" = "$m_md5" ]; then v="一致＝空替换"; SAME=$((SAME+1));
  elif [ "$s_size" = "无" ]; then v="原厂没有＝新增"; MISS=$((MISS+1));
  else v="不同＝真替换"; DIFF=$((DIFF+1)); fi
  printf "%-34s 原厂 %-9s %-12s %-19s | 模块 %-9s %-12s | %s\n" "$f" "$s_size" "$s_md5" "$s_mt" "$m_size" "$m_md5" "$v"
done
echo "----- 合计：一致 $SAME ／ 真替换 $DIFF ／ 新增 $MISS -----"
umount $T 2>/dev/null
