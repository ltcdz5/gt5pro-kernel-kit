#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt6a5.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# -a5 = 只套 include/linux/file.h(2 行: #include <linux/err.h> + DEFINE_FREE(fput,...))
# 与 -a4(blk-mq 那一对)互斥; 两版一起就构成"一次刷机判两件事"的另一半。
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 0) 自证: whoami / clang ==="
echo "  whoami=$(whoami)"; clang --version | head -1 | sed 's/^/  /'
echo "=== 1) opt5-state + 只套 file.h ==="
git checkout -q -f opt5-state
git checkout -q -B a5-fileh
git apply --check --include=include/linux/file.h /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply --include=include/linux/file.h /home/builder/opt6_upstream.patch
git status --porcelain | grep -E '^ M' | sed 's/^/    已改: /'
echo "=== 2) 后缀 -a5, 配置基准 opt5 ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a5"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"
echo "=== 3) 开编 $(date) ==="
rm -f out/Module.symvers
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -3
echo "=== 4) 存档 ==="
mkdir -p /home/builder/a5probe
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-60
cp -f out/vmlinux.symvers /home/builder/a5probe/vmlinux.symvers.a5
cp -f out/System.map /home/builder/a5probe/System.map.a5
cp -f out/arch/arm64/boot/Image /home/builder/a5probe/Image.a5
python3 - <<'PY'
def names(p):
    s=set()
    for L in open(p, errors='replace'):
        f=L.rstrip('\n').split('\t')
        if len(f)>=4: s.add(f[1])
    return s
a=names('/home/builder/opt5-baseline/Module.symvers'); c=names('/home/builder/a5probe/vmlinux.symvers.a5')
print("  vmlinux 导出数: opt5=%d a5=%d  新增=%s" % (len(a), len(c), sorted(c-a)))
PY
echo "=== 5) repack ==="
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /home/builder/a5probe/Image.a5 "$WIN/试验-a5-未真机验证.img" 2>&1 | tail -4
md5sum "$WIN/试验-a5-未真机验证.img"
echo "=== 结束 $(date) ==="
