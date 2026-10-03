#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo "=== 1) opt6 相对 opt5-state 到底动了哪些文件(应正好是那 25 个) ==="
git diff --stat opt5-state opt6 | tail -3
git diff --name-only opt5-state opt6 | wc -l | sed 's/^/  文件数: /'
echo
echo "=== 2) 被删掉的行里, 有没有 Oplus/BBG/我们自己东西的痕迹 ==="
git diff opt5-state opt6 | grep '^-' | grep -viE '^---' | grep -iE "oplus|bbg|baseband|hmbird|cctv|ltcdz5|BRUTAL|ssg|rekernel|lz4|zstd|rtmutex" | head -20
echo "  命中条数: $(git diff opt5-state opt6 | grep '^-' | grep -viE '^---' | grep -icE 'oplus|bbg|baseband|hmbird|cctv|ltcdz5|BRUTAL|ssg|rekernel|lz4|zstd|rtmutex')"
echo
echo '=== 3) 决定性检查: 这 25 个文件里, 有没有哪个是 cctv18/我们改过的(改过=会被官方版本覆盖=真丢东西) ==='
lost=0
for f in $(git diff --name-only opt5-state opt6); do
  if ! git diff --quiet 7a244ff18 opt5-state -- "$f" 2>/dev/null; then
    echo "  ! 该文件在 opt5 里与 cctv18 基线不同 => 官方版本覆盖了本地改动: $f"
    git diff --stat 7a244ff18 opt5-state -- "$f" | tail -2
    lost=$((lost+1))
  fi
done
echo "  会被覆盖的本地改动文件数: $lost"
echo
echo "=== 4) 我们那个提交碰过哪些文件(和 25 个求交集) ==="
git show --name-only --format="" 372750608 | sed '/^$/d' | sort > /tmp/ours.txt
git diff --name-only opt5-state opt6 | sort > /tmp/up25.txt
echo "  我们提交的文件数: $(wc -l < /tmp/ours.txt)"
echo '  交集(必须为空):' comm -12 /tmp/ours.txt /tmp/up25.txt | head -10
echo
echo "=== 5) 符号面: opt6 有没有少任何一个 opt5 有的符号/CRC(再确认一次) ==="
python3 - /home/builder/opt5-baseline/Module.symvers out/Module.symvers <<'PY'
def load(p):
    return {l.split('\t')[1]: l.split('\t')[0] for l in open(p) if '\t' in l}
a,b=load('/home/builder/opt5-baseline/Module.symvers'),load('out/Module.symvers')
print("  消失:", len(set(a)-set(b)), "| CRC 变化:", len([k for k in set(a)&set(b) if a[k]!=b[k]]), "| 新增:", len(set(b)-set(a)))
PY
echo
echo "=== 6) 配置面: opt6 的 out/.config 与 opt5 差异(应 0 行) ==="
diff /home/builder/opt5-baseline/config out/.config | grep -cE '^[<>]' | sed 's/^/  差异行数: /'
echo
echo "=== 7) 那 87 行删除具体删了什么(按文件) ==="
git diff opt5-state opt6 --stat | awk -F'|' '$2 ~ /-/ {print $1, $2}' | head -12
