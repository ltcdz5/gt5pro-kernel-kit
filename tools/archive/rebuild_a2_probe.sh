#!/bin/bash
# 复现 -a2 只为补齐三份读数(vmlinux/System.map/Module.symvers)。
# 不动 images/不能刷-裸内核/ 里那块当开机循环证据的原 Image。
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/a2probe
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
mkdir -p "$OUT"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
A2=(block/blk-mq.c include/linux/blk-mq.h include/linux/file.h android/abi_gki_aarch64_oplus)

echo "=== 1) opt5-state + 只套这 4 个文件 ==="
git checkout -q -f opt5-state
git checkout -q -B a2-probe
INC=""; for f in "${A2[@]}"; do INC="$INC --include=$f"; done
git apply --check $INC /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply $INC /home/builder/opt6_upstream.patch
git status --porcelain | grep '^ M' | sed 's/^/    已改: /'

echo "=== 2) 后缀 -a2p, 配置用 opt5 的实测 config ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a2p"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 3) 开编 $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -4
echo "=== 4) 存档三读数 + Image(新名字, 不覆盖证据) ==="
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-52
cp -f out/Module.symvers "$OUT/Module.symvers.a2probe"
cp -f out/System.map     "$OUT/System.map.a2probe"
cp -f out/arch/arm64/boot/Image "$OUT/Image.a2probe"
cp -f out/vmlinux "$OUT/vmlinux.a2probe"
md5sum "$OUT/Image.a2probe"
ls -l "$OUT"
echo "=== 结束 $(date) ==="
