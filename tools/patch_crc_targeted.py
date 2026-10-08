#!/usr/bin/env python3
# gt5pro-kernel-kit / tools/patch_crc_targeted.py
# 定点覆写内核 modversions CRC，使其与厂商 .ko 的 __versions 期望值一致。
# 每一条都必须有"无真实 ABI 差异"的证据（BTF/类型对账或纯标量原型），否则不许加进来。
# 用法: python tools/patch_crc_targeted.py <Image> [<vmlinux.symvers>]
import struct, sys, io, os

# (符号名, 本树算出的 CRC, 厂商期望 CRC, 依据)
OVERRIDES = [
    ("sk_filter_trim_cap", 0x43b2b8f0, 0xf5845708,
     "BTF 逐块对比证明 struct sk_buff/sock/sock_common 与出厂一致；bluetooth.ko 其余 96 个符号全匹配"),
    ("find_task_by_vpid", 0x5cd583b1, 0x5cd583b1,
     "原型为 struct task_struct *(pid_t)，纯标量参数、指针返回，无结构体传值/布局依赖"),
    ("iso_masks", 0xaee9c24f, 0xcb6a4c44,
     "oplus_bsp_sched_ext.ko 反汇编证明它按 4 个内嵌 cpumask 直接偏移访问："
     "exclusive@0x00 / partial@0x08 / big@0x10 / little@0x18，且为单次 ldr "
     "(addr = &iso_masks + (cpu/64)*8 + off)，无指针解引用 ⇒ 与我们的 "
     "cpumask_var_t(CONFIG_CPUMASK_OFFSTACK=n, NR_CPUS=32) 布局逐字段一致；"
     "CRC 差异只来自 genksyms 对匿名结构体成员名的展开"),
    ("task_is_scx", 0x61658a4e, 0xb3071c68,
     "原型 bool (struct task_struct *)：纯指针入参 + 标量返回，无结构体传值；"
     "模块把它作为 hmbird_ops_t 的第 0 个函数指针注册给 register_hmbird_sched_ops，"
     "签名逐位一致；CRC 差异只来自 genksyms 对 struct task_struct 定义可见性的展开"),
]

def main():
    if len(sys.argv) < 2:
        print("usage: patch_crc_targeted.py <Image> [<vmlinux.symvers>]")
        return 1
    img = sys.argv[1]
    d = bytearray(open(img, 'rb').read())
    for name, old, new, why in OVERRIDES:
        ob, nb = struct.pack('<I', old), struct.pack('<I', new)
        n = d.count(ob)
        if n != 1:
            print("SKIP %-24s 旧值 %#x 出现 %d 次（应为 1）" % (name, old, n))
            continue
        i = d.find(ob)
        d[i:i+4] = nb
        print("OK   %-24s %#x -> %#x @ %#x   [%s]" % (name, old, new, i, why))
    open(img, 'wb').write(bytes(d))
    if len(sys.argv) > 2 and os.path.exists(sys.argv[2]):
        p = sys.argv[2]
        t = io.open(p, encoding='utf-8').read()
        for name, old, new, why in OVERRIDES:
            t = t.replace('0x%08x\t%s' % (old, name), '0x%08x\t%s' % (new, name))
        io.open(p, 'w', encoding='utf-8', newline=chr(10)).write(t)
        print("symvers 已同步:", p)
    return 0

if __name__ == '__main__':
    sys.exit(main())
