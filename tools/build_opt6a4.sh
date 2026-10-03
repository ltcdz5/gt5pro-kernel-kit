#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt6a4.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# -a4 = 只套 blk-mq 那一对(1 行 EXPORT + 13 行头文件声明), 不含 include/linux/file.h
# 一次刷机判两件事:
#   循环开机 => 凶手是 test_task_ux 由 inline 变导出(块层热路径), file.h 无罪
#   能开机   => 凶手是 file.h 那 2 行(DEFINE_FREE/err.h), blk-mq 无罪
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
A4=(block/blk-mq.c include/linux/blk-mq.h)

echo "=== 0) 账号/编译器自证(防再犯 root 跑构建的错) ==="
echo "  whoami=$(whoami)  HOME=$HOME"
clang --version | head -1 | sed 's/^/  /'

echo "=== 1) opt5-state + 只套 blk-mq 这一对 ==="
git checkout -q -f opt5-state
git checkout -q -B a4-blkmq
INC=""; for f in "${A4[@]}"; do INC="$INC --include=$f"; done
git apply --check $INC /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply $INC /home/builder/opt6_upstream.patch
git status --porcelain | grep -E '^ M' | sed 's/^/    已改: /'
echo "  file.h 有没有被动: $(git status --porcelain | grep -c 'include/linux/file.h')"
echo "  白名单有没有被动: $(git status --porcelain | grep -c abi_gki_aarch64_oplus)"

echo "=== 2) 后缀 -a4, 配置用 opt5 实测 config ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a4"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 3) 清掉陈旧 symvers 再开编 $(date) ==="
rm -f out/Module.symvers
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -3

echo "=== 4) 存档(导出表用 vmlinux.symvers, 别读 Module.symvers) ==="
mkdir -p /home/builder/a4probe
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-120
ls -l --time-style=+%H:%M:%S out/vmlinux out/arch/arm64/boot/Image out/Module.symvers 2>&1 | sed 's/^/  /'
cp -f out/vmlinux.symvers /home/builder/a4probe/vmlinux.symvers.a4 2>/dev/null || cp -f out/Module.symvers /home/builder/a4probe/vmlinux.symvers.a4
cp -f out/System.map /home/builder/a4probe/System.map.a4
cp -f out/arch/arm64/boot/Image /home/builder/a4probe/Image.a4
python3 - <<'PY'
def names(p):
    s=set()
    for L in open(p, errors='replace'):
        f=L.rstrip('\n').split('\t')
        if len(f)>=4: s.add(f[1])
    return s
a=names('/home/builder/opt5-baseline/Module.symvers')
c=names('/home/builder/a4probe/vmlinux.symvers.a4')
print("  opt5=%d a4=%d 新增=%d 消失=%d" % (len(a),len(c),len(c-a),len(a-c)))
for x in sorted(c-a)[:10]: print("     +", x)
for x in sorted(a-c)[:10]: print("     -", x)
PY
echo "=== 5) repack ==="
cd /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /home/builder/a4probe/Image.a4 "$WIN/试验-a4-未真机验证.img" 2>&1 | tail -5
md5sum "$WIN/试验-a4-未真机验证.img"
echo "=== 结束 $(date) ==="
