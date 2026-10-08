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
    ("iso_masks", 0x9998675b, 0xcb6a4c44,
     "布局与出厂内核逐字段一致：出厂 BTF 的 struct scx_iso_masks = 40B / 5 x cpumask_var_t"
     "(ex_free@0, exclusive@8, partial@16, big@24, little@32)，本树 pahole -C scx_iso_masks 输出完全相同；"
     "oplus_bsp_sched_ext.ko 反汇编(cpu_util_policy_store)按原始偏移读 0x00/0x08/0x10 三次，与 5 成员布局吻合。"
     "CRC 差异是 genksyms 侧产物：实测 struct scx_iso_masks 只能算出 0x9998675b"
     "（改成员类型/加 __read_mostly/__aligned/const/数组/前置换 TU 上下文均不变），"
     "出厂 TU 的 0xcb6a4c44 无法从公开源复现 ⇒ 只能定点覆写"),
    ("task_is_scx", 0x61658a4e, 0xb3071c68,
     "实现已与出厂内核逐指令对齐（Image.stock task_is_scx @0x2ecb18：ldr x8,[x0,#832]; "
     "cmp &ext_sched_class; cset w0,eq; ret），原型 bool (struct task_struct *)：纯指针入参 + 标量返回，"
     "无结构体传值；模块把它作为 hmbird_ops_t 第 0 个函数指针注册给 register_hmbird_sched_ops，签名逐位一致；"
     "CRC 差异只来自 genksyms 对 struct task_struct 展开的差异"),
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
