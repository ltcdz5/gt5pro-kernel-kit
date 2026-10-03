#!/bin/bash
LOG=/c/Users/USERNAME/Desktop/wslcfg_log.txt
exec > "$LOG" 2>&1
echo "[$(date +%T)] start"

WC="/c/Users/USERNAME/.wslconfig"
echo "=== 1) 现有 .wslconfig ==="
if [ -f "$WC" ]; then
  cat "$WC"
  cp -f "$WC" "$WC.bak-$(date +%Y%m%d%H%M%S)" && echo "(已备份)"
else
  echo "(不存在，将新建)"
fi

echo
echo "=== 2) 写入新配置 ==="
cat > "$WC" <<'EOF'
[wsl2]
memory=24GB
networkingMode=mirrored
EOF
cat "$WC"

echo
echo "=== 3) 重启 WSL 让配置生效 ==="
wsl.exe --shutdown
sleep 5

echo
echo "=== 4) 验证镜像网络是否生效 ==="
wsl.exe -d Ubuntu-24.04 -e bash -lc 'echo "  default gw: $(ip route show default 2>/dev/null | awk "{print \$3}")"; echo "  ip 地址:"; ip -4 addr show 2>/dev/null | grep -oP "inet \K[0-9.]+" | head -5'

echo
echo "=== 5) 在 WSL 里配代理与 REPO_URL ==="
wsl.exe -d Ubuntu-24.04 -e bash -lc '
B="$HOME/.bashrc"
if ! grep -q "REPO_URL=" "$B" 2>/dev/null; then
  cat >> "$B" <<"RC"

# --- build env (added by setup) ---
export REPO_URL="https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
export http_proxy="http://127.0.0.1:7897"
export https_proxy="http://127.0.0.1:7897"
export no_proxy="localhost,127.0.0.1,::1,mirrors.aliyun.com,mirrors.tuna.tsinghua.edu.cn,172.27.0.0/16"
RC
  echo "  已写入 .bashrc"
else
  echo "  .bashrc 里已有配置，跳过"
fi
grep -A6 "build env" "$B"
'

echo
echo "=== 6) 测试(带代理的 shell) ==="
wsl.exe -d Ubuntu-24.04 -e bash -lc '
export REPO_URL="https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
export http_proxy="http://127.0.0.1:7897"
export https_proxy="http://127.0.0.1:7897"
echo "--- repo 自举测试 ---"
repo --version 2>&1 | head -2
echo "--- GitHub ---"
timeout 15 curl -sI -o /dev/null -w "  github.com     HTTP %{http_code}  %{time_total}s\n" https://github.com 2>&1 || echo "  github.com     FAIL"
timeout 15 curl -sI -o /dev/null -w "  googlesource   HTTP %{http_code}  %{time_total}s\n" https://android.googlesource.com 2>&1 || echo "  googlesource   FAIL"
timeout 15 curl -sI -o /dev/null -w "  阿里云(应直连) HTTP %{http_code}  %{time_total}s\n" https://mirrors.aliyun.com/ubuntu/dists/noble/Release 2>&1 || echo "  阿里云 FAIL"
'

echo "[$(date +%T)] done"
