#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/btf_full_diff.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 全类型 BTF 差异: 不止 struct/union, 而是 pahole 输出的每一种类型。
# 目的: 看"能开机的 opt5"和"循环开机的 -a/-a2"在类型层面是否真的完全等价。
cd /home/builder/abi/btf || exit 1
mkdir -p /home/builder/abi/full
for f in opt5-ltcdz5-raw CONTROL-opt5src-rebuilt opt7-clean opt6a-upstream opt6a2-upstream opt6-ltcdz5-up0914-raw; do
  [ -s /home/builder/abi/full/$f.txt ] || pahole $f.btf > /home/builder/abi/full/$f.txt 2>/dev/null
  printf '%-30s %8s 行  md5=%s\n' "$f" "$(wc -l < /home/builder/abi/full/$f.txt)" "$(md5sum < /home/builder/abi/full/$f.txt | cut -c1-12)"
done
echo
echo '================ opt5(能开) vs 各候选: 全类型差异 ================'
for f in CONTROL-opt5src-rebuilt opt7-clean opt6a-upstream opt6a2-upstream opt6-ltcdz5-up0914-raw; do
  n=$(diff /home/builder/abi/full/opt5-ltcdz5-raw.txt /home/builder/abi/full/$f.txt | grep -cE '^[<>]')
  echo "---- $f : 差异行数=$n"
  if [ "$n" != "0" ]; then
    diff /home/builder/abi/full/opt5-ltcdz5-raw.txt /home/builder/abi/full/$f.txt | head -30 | sed 's/^/     /'
  fi
done
