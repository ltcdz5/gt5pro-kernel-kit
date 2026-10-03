#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/cmp_btf.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
cd /home/builder/abi/btf || exit 1
B=opt5-ltcdz5-raw.btf
echo '基准 = opt5 (已知能开机)'
echo
for f in CONTROL-opt5src-rebuilt opt7-clean opt6a-upstream opt6a2-upstream opt6-ltcdz5-up0914-raw opt2b-ltcdz5-raw; do
  c=$f.btf
  if [ ! -s "$c" ]; then echo "$f : 文件缺失"; continue; fi
  if cmp -s "$B" "$c"; then
    verdict='BTF 逐字节完全一致'; off='-'
  else
    verdict='有差异'
    off=$(cmp "$B" "$c" 2>/dev/null | sed -E 's/.*byte ([0-9]+).*/\1/')
  fi
  printf '%-28s %-24s 首个差异字节=%s  大小 %s vs %s\n' "$f" "$verdict" "$off" \
        "$(stat -c%s "$B")" "$(stat -c%s "$c")"
done
echo
echo '=== BTF 覆盖到哪: 里面有没有函数? ==='
pahole $B > /tmp/p5.txt 2>/dev/null
wc -l /tmp/p5.txt
for fn in test_task_ux ep_poll vfs_read copy_process; do
  printf '  %-18s 在 pahole 全文里命中=%s\n' "$fn" "$(grep -c "$fn" /tmp/p5.txt)"
done
