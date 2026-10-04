#!/bin/bash
LOG=/c/Users/xutengfa/Desktop/zip_verify_log.txt
exec > "$LOG" 2>&1
echo "[$(date +%T)] 校验 E:\kworks 里的 zip 是否完整"

wsl.exe -d Ubuntu-24.04 -e bash -lc '
cd /mnt/e/kworks || exit 1
for z in *.zip ; do
  echo "=== $z ==="
  out=$(unzip -t "$z" 2>&1 | tail -3)
  if echo "$out" | grep -qi "No errors detected"; then
    n=$(unzip -l "$z" 2>/dev/null | tail -1 | awk "{print \$2}")
    echo "  ✅ 完整  ($n 个文件)"
  else
    echo "  ❌ 有问题:"
    echo "$out" | sed "s/^/     /"
  fi
done
'
echo "[$(date +%T)] done"
