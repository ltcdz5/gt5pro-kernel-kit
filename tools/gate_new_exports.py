#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate_new_exports.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
"""
闸门: 内核镜像(vmlinux)的导出集变化 ∩ 厂商 .ko 引用名 == 空
      新增 与 消失 两侧都要判 —— 符号消失同样致命。

机理: Android 的 modpost 会把"不在 KMI 白名单里"的外部符号引用编成 weak undefined。
      内核不导出该符号时, 厂商 .ko 拿到 NULL, 走"跳过"分支;
      我们一旦把它导出, 守卫翻成"真调用", 而实现读的是厂商模块不认识的内核状态
      => 活锁 => PMIC 看门狗硬复位(pstore 无记录, bootreason=pmic)。
      反向同理: 原本能取到的符号消失, 厂商 .ko 会拒绝装载或走错分支。
CRC 照不到这两类: 两边都有的符号一个都没变, 变的是"集合本身"。

---- 2026-10-01 修复(见 kernel-kit/工具链审计-20261001.md §二.①) ----
1) 补上"消失导出"判定。原版全文只有 `new = cand - base`, 没有 `base - cand`,
   而四份文档都承诺两侧都要判 => 任何减少厂商引用名的改动原本一律 PASS。
2) 基准口径修正。原版基准是 opt5 的 Module.symvers(= vmlinux 导出 + 364 个 =m 模块导出),
   而候选是 out/vmlinux.symvers(只有 vmlinux) => 口径不一致,
   "由 =m 模块导出改成 vmlinux 导出"的符号会落进基准、被 new 集合排除、闸门看不见。
   现改为: 两侧都只取第 3 列 == "vmlinux" 的行(该列是符号来源模块)。
   实测: opt5 Module.symvers 15752 行中 vmlinux 行 = 15388, 与 opt13 的 vmlinux.symvers 完全一致。
3) 输入缺失改为 fail-closed。原版: 不传参数 / 0 字节候选 / 截断候选 三种都输出 PASS 且 rc=0。
   现在: 无参数、文件不存在、0 字节、解析出 0 个导出 => rc=2(错误), 绝不给 PASS。
4) 退出码语义: 0=全部通过, 1=命中砖闸, 2=输入/基准错误。调用方必须检查(见 §调用点纪律)。

---- 2026-10-03 修复: 基准本身是错的(见 kernel-kit/厂商模块导出依赖表-20261003.md §2) ----
5) **旧基准 vko_syms.txt 不是符号表, 是 `strings -a` 转储。** 实测:
   · 493 个 .ko 的真实 UND 引用名并集只有 4754 条; 旧基准有 199295 条 => 195138 条(98%)是噪声
     (GPU 寄存器名/枚举名/protobuf 描述符等字符串)。
   · 同时**漏掉 595 条真引用**, 其中 586 条来自 system_dlkm(该分区 49.4% 的引用名闸门看不见) ——
     因为当年 dump 命令没包含 /system_dlkm/lib/modules/。
   · 后果一(假阳性): 任何"恰好作为字符串出现在某个 .ko 里"的新增导出名都会被判砖。
     实测: 2026-10-02 P28 那次对 `prep_new_page` 的 FAIL 就是假阳性 ——
     真 ELF 解析下**没有任何 .ko 引用 prep_new_page**。(那次回退本身无害, 但结论要更正。)
   · 后果二(假阴性): 新增导出若被某个 system_dlkm 模块真引用, 旧基准看不见 => 会误判 PASS。
   现改为: **真基准(ELF 解析, vko_syms_real.txt)是权威判定**;
   旧基准降级为**提示**(命中只打印警告, 不判 FAIL), 信息不丢且不再误判。

用法:
    gate_new_exports.py <候选 symvers> [更多候选...]
"""
import sys
import os

VKO_REAL = '/home/builder/abi/vko_syms_real.txt'   # ★权威: 真 ELF 解析的 UND 引用名并集 (4754 条)
VKO = '/home/builder/abi/vko_syms.txt'             # 仅作提示: strings 转储 (199295 条, 98% 噪声)
BASE = '/home/builder/opt5-baseline/Module.symvers'   # 能开机内核的导出全表(含模块导出, 内部按口径过滤)

# 候选导出数低于基准的这个比例时告警(候选可能被截断)
FLOOR_RATIO = 0.90

EXIT_PASS = 0
EXIT_BRICK = 1
EXIT_ERROR = 2


def read_symvers(path):
    """解析 symvers。格式(制表符分隔):
       0xCRC <TAB> name <TAB> module <TAB> EXPORT_TYPE [<TAB> namespace]

    返回 (vmlinux_exports, module_exports)。
    module 列 == 'vmlinux' 的是内核镜像导出(判定用); 其余是 =m 模块导出(仅参考)。
    """
    vm, mod = set(), set()
    with open(path, errors='replace') as f:
        for line in f:
            t = line.rstrip('\n').split('\t')
            if len(t) >= 4 and t[1]:
                if t[2] == 'vmlinux':
                    vm.add(t[1])
                else:
                    mod.add(t[1])
    return vm, mod


def main():
    args = sys.argv[1:]

    # ---- 输入校验: 一律 fail-closed ----
    if not args:
        print("错误: 没有传候选文件。")
        print("      这个闸门在无输入时不能给 PASS —— 那正是它以前假通过的路径。")
        print("用法: %s <候选 symvers> [更多候选...]" % os.path.basename(sys.argv[0]))
        return EXIT_ERROR
    if not os.path.exists(VKO_REAL):
        print("错误: 缺【权威】厂商基准 %s" % VKO_REAL)
        print("      它是真 ELF 解析的 UND 引用名并集; 生成命令见")
        print("      kernel-kit/厂商模块导出依赖表-20261003.md (重建脚本: rebuild_vko.py)")
        return EXIT_ERROR
    vko_real = set(x.strip() for x in open(VKO_REAL, errors='replace') if x.strip())
    if not vko_real:
        print("错误: 权威基准 %s 为空" % VKO_REAL)
        return EXIT_ERROR
    vko_adv = set()
    if os.path.exists(VKO):
        vko_adv = set(x.strip() for x in open(VKO, errors='replace') if x.strip())
    if not os.path.exists(BASE):
        print("错误: 缺基准 %s" % BASE)
        return EXIT_ERROR
    if os.path.getsize(BASE) == 0:
        print("错误: 基准 %s 是 0 字节" % BASE)
        return EXIT_ERROR

    base_vm, base_mod = read_symvers(BASE)
    if not base_vm:
        print("错误: 基准里解析出 0 个 vmlinux 导出 —— 口径解析失败, 拒绝出结论")
        return EXIT_ERROR

    print("厂商基准(权威/ELF) .ko 引用名 = %d 个" % len(vko_real))
    print("厂商基准(提示/strings)         = %d 个   [98%% 噪声, 仅作参考]" % len(vko_adv))
    print("基准内核(vmlinux)导出 = %d 个   [另有 %d 个 =m 模块导出, 不参与判定]"
          % (len(base_vm), len(base_mod)))
    print("=" * 84)

    rc = EXIT_PASS
    for path in args:
        name = os.path.basename(path)

        if not os.path.exists(path):
            print("%-30s 错误: 候选文件不存在 -> 拒绝 PASS" % name)
            rc = EXIT_ERROR
            continue
        if os.path.getsize(path) == 0:
            print("%-30s 错误: 候选文件 0 字节 -> 拒绝 PASS" % name)
            rc = EXIT_ERROR
            continue

        cand_vm, cand_mod = read_symvers(path)
        if not cand_vm:
            print("%-30s 错误: 解析出 0 个 vmlinux 导出 -> 拒绝 PASS" % name)
            rc = EXIT_ERROR
            continue

        # 候选导出数明显低于基准 => 这是"输入被截断/构建残缺", 不是"砖"。
        # 报成输入错误(rc=2)并跳过判定, 免得把残缺候选误诊成砖版。
        if len(cand_vm) < len(base_vm) * FLOOR_RATIO:
            print("%-30s 错误: vmlinux 导出仅 %d 个, 基准 %d 个 (低于 %.0f%%) —— 候选被截断或构建残缺,"
                  " 拒绝出判定" % (name, len(cand_vm), len(base_vm), FLOOR_RATIO * 100))
            rc = EXIT_ERROR
            continue

        added = cand_vm - base_vm
        gone = base_vm - cand_vm
        hit_add = sorted(added & vko_real)
        hit_gone = sorted(gone & vko_real)
        adv_add = sorted(added & vko_adv)
        adv_gone = sorted(gone & vko_adv)

        verdict = 'FAIL 判砖' if (hit_add or hit_gone) else 'PASS'
        print("%-30s 新增=%-5d 消失=%-5d | 命中厂商: 新增=%-4d 消失=%-4d  %s"
              % (name, len(added), len(gone), len(hit_add), len(hit_gone), verdict))
        # 旧基准的命中只作提示(它有 98% 噪声, 不能判 FAIL)
        adv_only_add = [x for x in adv_add if x not in hit_add]
        adv_only_gone = [x for x in adv_gone if x not in hit_gone]
        if adv_only_add or adv_only_gone:
            print("      ℹ 旧(strings)基准另有命中 %d+%d 个 —— 仅提示, 不判 FAIL"
                  " (它 98%% 是字符串噪声; 例: prep_new_page 就是假阳性)"
                  % (len(adv_only_add), len(adv_only_gone)))
            for h in adv_only_add[:5]:
                print("          (提示) 新增 %s" % h)

        for h in hit_add[:12]:
            print("      ⚠ 新增导出 %s   (基准未导出; 厂商 .ko 引用这个名字 => 守卫会翻成真调用)" % h)
        if len(hit_add) > 12:
            print("      ... 另有 %d 个新增命中未列出" % (len(hit_add) - 12))
        for h in hit_gone[:12]:
            print("      ⚠ 消失导出 %s   (厂商 .ko 引用这个名字 => 符号消失同样致命)" % h)
        if len(hit_gone) > 12:
            print("      ... 另有 %d 个消失命中未列出" % (len(hit_gone) - 12))

        if hit_add or hit_gone:
            rc = EXIT_BRICK

        # 模块导出漂移: 仅当候选本身带模块导出(即传的是 Module.symvers)时才有意义
        if cand_mod:
            m_add = len(cand_mod - base_mod)
            m_gone = len(base_mod - cand_mod)
            if m_add or m_gone:
                print("      (参考, 不参与判定: =m 模块导出 新增=%d 消失=%d)" % (m_add, m_gone))

    print("=" * 84)
    print("退出码 %d  (0=全部通过, 1=命中砖闸, 2=输入/基准错误)" % rc)
    return rc


if __name__ == '__main__':
    sys.exit(main())
