#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt10.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt10 = opt9 + stable 6.1.142..145 中能整文件干净落地的 133 文件子集
# 只做: 编 -> 读横幅 -> 新导出闸 -> 与 opt5 的全类型布局比对 -> repack 到"未刷"文件
set -u
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt10probe
W=/home/builder/opt10
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
mkdir -p "$OUT" "$W"

echo "=== 0) 自证 $(date) ==="
echo "  whoami=$(whoami)"; clang --version | head -1 | sed 's/^/  /'
echo "  分支=$(git rev-parse --abbrev-ref HEAD)  改动文件=$(git diff --name-only | wc -l)"

echo '=== 1) 配置基准 = opt9 实测 out/.config ==='
cp -f out/.config "$W/config.opt9"
echo "  已存 $W/config.opt9 ($(wc -l < "$W/config.opt9") 行)"

echo '=== 2) 后缀 -opt10 ==='
sed -i 's/^echo "-android14-11-o-ltcdz5-opt9"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion
sed -i 's/^echo "-android14-11-o-ltcdz5-clean"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion
echo "  $(tail -1 scripts/setlocalversion)"

echo '=== 3) 只修未来时间戳, 保住增量编译 ==='
NOW=$(date +%s)
BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null | wc -l)
echo "  未来时间戳文件数=$BAD"
if [ "$BAD" -gt 0 ]; then
  find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null
  echo "  已归一 -> $(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null | wc -l)"
fi

echo '=== 4) olddefconfig ==='
eval make -j"$(nproc --all)" $MFLAGS olddefconfig 2>&1 | tail -2
echo "  config 与 opt9 差异行数=$(diff "$W/config.opt9" out/.config | grep -cE '^[<>]')"
diff "$W/config.opt9" out/.config | grep -E '^[<>]' | head -8 | sed 's/^/    /'

echo "=== 5) 开编 $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image > /tmp/o10.log 2>&1
RC=$?
echo "  make 退出码=$RC  用时见末尾"
grep -iE 'clock skew' /tmp/o10.log | head -2 | sed 's/^/  /'
echo "  clock skew 警告数=$(grep -ciE 'clock skew' /tmp/o10.log)"
grep -iE ' error|Error ' /tmp/o10.log | head -8 | sed 's/^/  ⛔ /'
[ $RC -ne 0 ] && { echo "  ⛔ 构建失败, 日志尾:"; tail -15 /tmp/o10.log; exit 1; }

echo '=== 6) 读数 + 闸门 ==='
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-64 | sed 's/^/  /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt10"
cp -f out/System.map "$OUT/System.map.opt10"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt10"
md5sum "$OUT/Image.opt10" | sed 's/^/  /'
echo "  test_task_ux 镜像内=$(strings -a $OUT/Image.opt10 | grep -c test_task_ux)  opt5基线=$(strings -a $BASE/Image.opt5 | grep -c test_task_ux)"
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt10"

echo '=== 7) 全类型布局比对 opt10 vs opt5 ==='
python3 - <<'PY'
import struct
PAT = bytes([0x9f, 0xeb, 0x01, 0x00, 0x18, 0x00, 0x00, 0x00])
d = open('/home/builder/opt10probe/Image.opt10', 'rb').read()
h = d.find(PAT)
to, tl, so, sl = struct.unpack_from('<IIII', d, h + 8)
open('/home/builder/abi/btf/opt10.btf', 'wb').write(d[h:h + 24 + to + tl + so + sl])
print('  抠出 BTF 字节=%d' % (24 + to + tl + so + sl))
PY
pahole /home/builder/abi/btf/opt10.btf > /home/builder/abi/full/opt10.txt 2>/dev/null
echo "  类型行数 opt10=$(wc -l < /home/builder/abi/full/opt10.txt)  opt5=$(wc -l < /home/builder/abi/full/opt5.txt)"
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -cE '^[<>]')  (opt9 当时=0, opt8=12)"
diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -E '^[<>]' | head -20 | sed 's/^/    /'

echo '=== 8) repack 到未刷文件 ==='
cd /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py "$OUT/Image.opt10" /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/试验-opt10-未真机验证.img 2>&1 | tail -5
echo "=== 结束 $(date) ==="
