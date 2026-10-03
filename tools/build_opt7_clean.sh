#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt7_clean.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt7-clean = opt5 源码 + 拆掉 builder 注入的 config_fix + gki_defconfig 去重 + 清工作区垃圾
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 1) 从 opt5-state 开 opt7-clean ==="
git checkout -q -f opt5-state
git checkout -q -B opt7-clean
rm -f config.patch.[0-9]* cve-2026-43499-rtmutex-6.1.patch.[0-9]* 2>/dev/null || true
echo "  未跟踪垃圾文件数: $(git status --porcelain | grep -c '^??')"

echo "=== 2) 拆掉 kernel/Makefile 里的 config_fix(还原成上游四行) ==="
python3 - <<'PY'
import io,re
p='kernel/Makefile'
s=io.open(p,encoding='utf-8',errors='replace').read()
if 'config_fix' not in s:
    print("   已经没有 config_fix, 跳过"); raise SystemExit(0)
new = re.sub(r'define config_fix\n.*?\nendef\n\n', '', s, flags=re.S)
new = new.replace('\t$(call filechk,cat)\n\t$(Q)$(config_fix)\n', '\t$(call filechk,cat)\n')
assert 'config_fix' not in new, "没拆干净!"
io.open(p,'w',newline='\n',encoding='utf-8').write(new)
print("   已拆除; 该文件残留 config_fix 次数:", new.count('config_fix'))
PY
sed -n '/^filechk_cat/,/^\$(obj)\/kheaders.o/p' kernel/Makefile | sed 's/^/     /'

echo "=== 3) gki_defconfig 去重(重复键按 opt5 实测 config 取值, 只留一条) ==="
python3 - <<'PY'
import io,re,collections
auth={}
for L in io.open('/home/builder/opt5-baseline/config',encoding='utf-8',errors='replace'):
    m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L.strip())
    if m: auth[m.group(1)]=m.group(2)
    else:
        m=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L.strip())
        if m: auth[m.group(1)]='n'
p='arch/arm64/configs/gki_defconfig'
lines=io.open(p,encoding='utf-8',errors='replace').read().split('\n')
seen=set(); out=[]; dropped=0; fixed=0
for L in lines:
    m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L.strip())
    n=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L.strip())
    k=(m or n).group(1) if (m or n) else None
    if k:
        if k in seen:
            dropped+=1; continue
        seen.add(k)
        if k in auth:
            want=auth[k]
            norm=(m.group(2) if m else 'n')
            if norm!=want:
                fixed+=1
                L = (f"{k}={want}" if want!='n' else f"# {k} is not set")
    out.append(L)
# 注: 不动 CONFIG_HEADERS_INSTALL —— 它是给工具链导出 uapi 头用的构建选项, 对手机零意义,
#     改它会让 .config 变动(还会连带 UAPI_HEADER_TEST) ⇒ 触发全量重编并制造"与现役配置不一致"。
txt='\n'.join(out)
io.open(p,'w',newline='\n',encoding='utf-8').write(txt)
print(f"   丢弃重复行 {dropped} 条, 按基准改正 {fixed} 条")
import collections
c=collections.Counter(l.split('=')[0] for l in txt.split('\n') if l.startswith('CONFIG_'))
print("   新行数:", len(txt.split('\n')), " 剩余重复键:", sum(1 for k,v in c.items() if v>1))
PY

echo "=== 4) 版本后缀 ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-clean"/' scripts/setlocalversion
tail -1 scripts/setlocalversion

echo "=== 5) 用去重后的 gki_defconfig 走正规流程生成 config 并与 opt5 基准比 ==="
rm -rf out/.config
eval make -j"$(nproc --all)" $MFLAGS gki_defconfig >/dev/null 2>&1 || eval make $MFLAGS gki_defconfig
diff <(sort "$BASE/config") <(sort out/.config) | grep -E "^[<>]" | head -12
echo "  与 opt5 config 差异行数: $(diff <(sort "$BASE/config") <(sort out/.config) | grep -cE '^[<>]')"

echo "=== 6) 开编 $(date) ==="
if [ "$1" = "--pre" ]; then echo "  (--pre 模式: 按要求停在编译前)"; exit 0; fi
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -6
git add -A
git -c user.name=ltcdz5 -c user.email=ltcdz5@users.noreply.github.com commit -q -m "opt7-clean: 拆除 builder 注入的 config_fix(不再谎报 IP6_NF_NAT) + gki_defconfig 去重 + HEADERS_INSTALL 对齐原厂"
echo "  opt7-clean = $(git rev-parse --short HEAD)"
ls -la out/arch/arm64/boot/Image; md5sum out/arch/arm64/boot/Image
