#!/bin/bash
set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH
# 版本串 -> opt47
python3 - <<'PY'
import io
p='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/scripts/setlocalversion'
s=io.open(p,encoding='utf-8').read()
s2=s.replace('-android14-11-o-ltcdz5-v1.1-opt45','-android14-11-o-ltcdz5-v1.1-opt47')
assert s2!=s, 'setlocalversion 没改到'
io.open(p,'w',encoding='utf-8').write(s2)
print('setlocalversion -> opt47')
PY
git add drivers/i2c/i2c-core-base.c scripts/setlocalversion
git -c user.name=ltcdz5 -c user.email=ltcdz5@local commit -q -m "v1.1-opt47：i2c 适配器注册竞态 + 失败路径补漏（取自 ACK 10-02 两条）

来源：ACK android14-6.1-lts（权威源）
  - 1febb174815b  i2c: core: fix adapter registration race
  - e984010cda7d  i2c: core: fix adapter debugfs creation（只取其『dev_set_name 判返回值 +
                  失败路径拆 Host Notify IRQ domain』两个附带收益）

改动（全部在函数体内，零结构体、零导出）：
  1. i2c_add_adapter() / __i2c_add_numbered_adapter()：idr_alloc 的 payload 由 adap 改为 NULL
     => id 先占位，适配器指针不再在注册途中就对别人可见
  2. i2c_register_adapter()：在 device_register() 之前用 idr_replace() 公布真指针（持 core_lock）
  3. dev_set_name() 判返回值，失败走错误路径
  4. 新增 err_remove_irq_domain 标签：device_register/名字设置失败时补 i2c_host_notify_irq_teardown()
     （我们树原来这两条失败路径会漏拆 irq domain）

未取的部分：e984010cda7d 的 adap->debugfs 会给 struct i2c_adapter 加成员，
而 i2c_add_adapter() 等是导出符号 => CRC 会漂移 => 正中闸门2，故不取。"
git log --oneline -1
echo
echo '=== 起构（banner #74）==='
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
eval make -j"$(nproc)" $MFLAGS KBUILD_BUILD_VERSION="74-ack304-v1.1-opt47" Image 2>&1 | tail -12
echo "make rc=$(echo ${PIPESTATUS[0]})"
ls -l out/arch/arm64/boot/Image
strings -a out/arch/arm64/boot/Image | grep -m1 'Linux version 6.1.141'