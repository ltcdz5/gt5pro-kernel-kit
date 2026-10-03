#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
IC=$BASE/ic6.txt
./scripts/extract-ikconfig out/arch/arm64/boot/Image > "$IC" || zcat out/config.gz > "$IC" 2>/dev/null || cp out/.config "$IC"
echo "ikconfig 行数: $(wc -l < "$IC")"
echo
echo "=== 内核里不能有内置 KSU(要 LKM 走 init_boot) ==="
echo "  含 ksu 的行数: $(grep -ci ksu "$IC")"
grep -i ksu "$IC" | head -3
echo
echo "=== opt6 相对 opt5 的 config 差异 ==="
diff <(sort "$BASE/config") <(sort "$IC") | grep -E "^[<>]" > "$BASE/cfg.diff" || true
echo "  差异行数: $(wc -l < "$BASE/cfg.diff")"
cat "$BASE/cfg.diff" | head -25
echo
echo "=== gki_defconfig 有没有被 builder 再次堆重复(清理法要求) ==="
F=arch/arm64/configs/gki_defconfig
echo "  总行数 $(wc -l < $F) | 重复配置键数 $(grep '^CONFIG_' $F | sed 's/=.*//' | sort | uniq -d | wc -l)"
echo "  文件出现次数>1 的键:"; grep '^CONFIG_' $F | sed 's/=.*//' | sort | uniq -c | awk '$1>1' | head -10
echo
echo "=== 本轮 git 状态 ==="
git rev-parse --abbrev-ref HEAD; git log --oneline -2 | cut -c1-100
git status --porcelain | head -8
