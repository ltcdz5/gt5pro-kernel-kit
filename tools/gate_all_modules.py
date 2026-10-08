#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate_all_modules.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
# ---------------------------------------------------------------------------
"""
全量厂商模块审计（闸门2 的补集）: 逐 .ko 比对 __versions 期望值 vs 候选内核/模块导出

为什么需要它（gate_vko_crc.py 的盲区）:
  gate_vko_crc.py 只比「已存在符号」的 CRC —— 内核没导出的符号它直接 continue 跳过，
  所以「符号缺失」它完全看不见。实测漏掉过：
    · oplus_bsp_sched_ext 的 7 个缺符号（iso_masks / ext_module_loaded /
      get_hmbird_cpu_exclusive / task_is_scx / scx_get_md_info / non_ext_task / hmbird_dir）
    · opt51（关 KASAN/KFENCE/DEBUG_LIST/... ）: __list_add_valid 等导出直接消失，
      493/493 模块全坏，旧闸门却只报「拒载 = 1」。
  本脚本同时报两件事：
    ① 缺失    : __versions 里的符号，内核与全部厂商模块都不导出 ⇒ 装载时 Unknown symbol
    ② CRC不符 : 内核导出了该符号，但 CRC 与厂商期望不等 ⇒ disagrees about version

符号全集（universe）= 下面三者的并集，缺一不可：
  1. <tree_dir>/out/vmlinux.symvers              候选内核自带的导出（+ 用于 CRC 比对）
  2. 各 <vendor-ko_dir> 下 .ko 的 __ksymtab_strings   随包刷入的厂商模块导出
  3. 外部参考导出快照（默认 refs/mod-exports-622mods-4623.txt）
     设备上还有约 130 个不在 vendor-ko 镜像里的原厂模块（qcom_ipc_logging / smem /
     boot_mode / socinfo / qcom_scm …），它们的导出是固定的，必须计入 —— 否则出现大量
     假阳性：实测只算 1+2 时 178 个模块报缺失，加上 3 后收敛到真正出问题的那 1 个
     （与设备 dmesg 的 Unknown symbol 逐条对上）。

用法:
  gate_all_modules.py [<tree_dir> [<vendor-ko_dir> ...]] [--extra-exports FILE]... [--no-extra]
  不给参数时用默认值（WSL 内核树 + 两个厂商 .ko 目录）。
退出码: 0 = 全绿（缺失 = 0 且 CRC 不符 = 0）, 1 = 有模块出问题, 2 = 输入错误
"""
import glob
import io
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TREE = '/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
DEFAULT_KO_DIRS = [
    '/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm',
    '/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/system_dlkm',
]
# 设备 622 个模块的 __ksymtab 并集（4623 条）；闸门1 的模块侧基准，也是本脚本的外部参考
DEFAULT_EXTRA = os.path.normpath(os.path.join(HERE, '..', 'refs', 'mod-exports-622mods-4623.txt'))


def elf_sections(data):
    """返回 [(name, offset, size), ...]；只做 64 位小端 ELF。"""
    if len(data) < 64 or data[:4] != b'\x7fELF':
        return []
    if data[4] != 2 or data[5] != 1:          # 64 位 / 小端
        return []
    e_shoff, = struct.unpack_from('<Q', data, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    if e_shoff == 0 or e_shnum == 0:
        return []
    shs = []
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        if base + 64 > len(data):
            break
        name_off, = struct.unpack_from('<I', data, base)
        sh_off, = struct.unpack_from('<Q', data, base + 0x18)
        sh_size, = struct.unpack_from('<Q', data, base + 0x20)
        shs.append((name_off, sh_off, sh_size))
    if e_shstrndx >= len(shs):
        return []
    stroff = shs[e_shstrndx][1]
    out = []
    for name_off, sh_off, sh_size in shs:
        end = data.find(b'\0', stroff + name_off)
        nm = data[stroff + name_off:end].decode('utf-8', 'replace') if end > 0 else ''
        out.append((nm, sh_off, sh_size))
    return out


def ko_exports(path):
    """模块自己导出的符号（__ksymtab_strings）。"""
    try:
        data = io.open(path, 'rb').read()
    except OSError:
        return set()
    names = set()
    for nm, off, size in elf_sections(data):
        if nm == '__ksymtab_strings' and size:
            for s in data[off:off + size].split(b'\0'):
                if s:
                    names.add(s.decode('utf-8', 'replace'))
    return names


def ko_versions(path):
    """模块期望的 (crc, symbol) 列表（__versions 节，每项 64 字节）。"""
    try:
        data = io.open(path, 'rb').read()
    except OSError:
        return []
    for nm, off, size in elf_sections(data):
        if nm == '__versions' and size:
            out = []
            for i in range(0, size - 63, 64):
                crc, = struct.unpack_from('<Q', data, off + i)
                name = data[off + i + 8:off + i + 8 + 56].split(b'\0')[0]
                if name:
                    out.append(('0x%08x' % (crc & 0xFFFFFFFF),
                                name.decode('utf-8', 'replace')))
            return out
    return []


def read_symvers(path):
    """候选内核导出 {symbol: '0x%08x'}。"""
    out = {}
    with io.open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            t = line.rstrip('\n').split('\t')
            if len(t) >= 2 and t[1]:
                try:
                    out[t[1]] = '0x%08x' % (int(t[0], 16) & 0xFFFFFFFF)
                except ValueError:
                    continue
    return out


def read_extra(path):
    """外部参考导出快照（每行一个符号名）。"""
    out = set()
    try:
        with io.open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith('#'):
                    out.add(s)
    except OSError:
        return None
    return out


def main(argv):
    args, extras, no_extra = [], [], False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--extra-exports':
            i += 1
            if i >= len(argv):
                print('错误: --extra-exports 缺参数'); return 2
            extras.append(argv[i])
        elif a == '--no-extra':
            no_extra = True
        elif a in ('-h', '--help'):
            print(__doc__); return 0
        elif a.startswith('-'):
            print('错误: 未知选项 %s' % a); return 2
        else:
            args.append(a)
        i += 1

    tree = args[0] if args else DEFAULT_TREE
    ko_dirs = args[1:] if len(args) > 1 else list(DEFAULT_KO_DIRS)

    symvers = os.path.join(tree, 'out', 'vmlinux.symvers')
    if not os.path.exists(symvers) or os.path.getsize(symvers) == 0:
        print('错误: 候选 %s 不存在或为空 -> 拒绝出结论' % symvers); return 2
    kernel_exp = read_symvers(symvers)
    if not kernel_exp:
        print('错误: 候选 %s 解析出 0 个导出' % symvers); return 2

    kos = []
    for d in ko_dirs:
        if not os.path.isdir(d):
            print('错误: 厂商模块目录不存在 %s' % d); return 2
        for root, _dd, files in os.walk(d):
            for fn in files:
                if fn.endswith('.ko'):
                    kos.append(os.path.join(root, fn))
    if not kos:
        print('错误: 没找到任何 .ko'); return 2

    ko_exp = {}
    for k in kos:
        ko_exp[k] = ko_exports(k)
    module_exp = set()
    for s in ko_exp.values():
        module_exp |= s

    extra_sets, extra_desc = [], []
    if not no_extra:
        for p in (extras or [DEFAULT_EXTRA]):
            s = read_extra(p)
            if s is None:
                if extras:
                    print('错误: 外部参考导出 %s 不存在' % p); return 2
                extra_desc.append('(缺 %s, 已跳过)' % p)
                continue
            extra_sets.append(s)
            extra_desc.append('%s (%d)' % (p, len(s)))
    extra_exp = set()
    for s in extra_sets:
        extra_exp |= s

    universe = set(kernel_exp) | module_exp | extra_exp

    print('候选内核   : %s' % symvers)
    print('内核导出   = %d' % len(kernel_exp))
    print('厂商模块   = %d 个，模块导出 = %d' % (len(kos), len(module_exp)))
    for d in extra_desc:
        print('外部参考   = %s' % d)
    print('符号全集   = %d（内核 ∪ 厂商模块 ∪ 外部参考）' % len(universe))
    print('=' * 88)

    bad = []
    n_parsed = 0
    miss_freq = {}
    for k in kos:
        vers = ko_versions(k)
        if not vers:
            continue
        n_parsed += 1
        miss = [s for _c, s in vers if s not in universe]
        crc = [(s, want, kernel_exp[s]) for want, s in vers
               if s in kernel_exp and kernel_exp[s] != want]
        if miss or crc:
            bad.append((os.path.basename(k), miss, crc))
            for s in miss:
                miss_freq[s] = miss_freq.get(s, 0) + 1

    print('解析成功 %d 个模块；有问题 = %d 个（缺失>0 或 CRC不符>0）'
          % (n_parsed, len(bad)))
    if bad:
        print('-' * 88)
        for name, miss, crc in sorted(bad)[:40]:
            print('  %-42s 缺失=%-4d CRC不符=%d' % (name, len(miss), len(crc)))
            for s in miss[:6]:
                print('        缺: %s' % s)
            if len(miss) > 6:
                print('        缺: ... 另有 %d 个' % (len(miss) - 6))
            for s, want, have in crc[:6]:
                print('        CRC: %-38s 厂商期望=%s 本内核=%s' % (s, want, have))
            if len(crc) > 6:
                print('        CRC: ... 另有 %d 个' % (len(crc) - 6))
        if len(bad) > 40:
            print('  ... 另有 %d 个问题模块（只列前 40）' % (len(bad) - 40))
        if miss_freq:
            print('-' * 88)
            print('缺失符号出现次数 top 12:')
            for s, n in sorted(miss_freq.items(), key=lambda x: -x[1])[:12]:
                print('   %-44s %d 个模块' % (s, n))
    print('=' * 88)
    n_miss = sum(len(m) for _n, m, _c in bad)
    n_crc = sum(len(c) for _n, _m, c in bad)
    if bad:
        print('判定: FAIL  缺失>0 或 CRC不符>0 的模块 = %d（缺失符号 %d 处，CRC 不符 %d 处）'
              % (len(bad), n_miss, n_crc))
        print('VERDICT: FAIL modules=%d missing=%d crc=%d' % (len(bad), n_miss, n_crc))
        return 1
    print('判定: PASS  %d 个模块全部可装载（缺失=0 CRC不符=0）' % n_parsed)
    print('VERDICT: PASS modules=%d missing=0 crc=0' % n_parsed)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
