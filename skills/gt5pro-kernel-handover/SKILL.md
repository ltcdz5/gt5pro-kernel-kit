---
name: gt5pro-kernel-handover
description: 接手真我 GT5 Pro（RMX3888 / RE5C37 / SM8650 "pineapple" / Android 16 / GKI 6.1.141 / KernelSU LKM）自编内核与 KSU 模块维护的完整工作流。用于继续或交接该项目：查现役版本与 md5、重编/出件/过砖闸/刷入/验收/回退，改 KSU 模块，取冷启动与功耗基线，判"改动进没进本机"，以及避开本机已踩实的工具坑（adb/fastboot/WSL/Bash 通道、debugfs 随机名、只读重挂 vendor 等）。当任务涉及 opt 系列内核、boot_a 刷写、vmlinux.a 判据、vendor-ko 符号闸、lru_gen_on/某第三方 GPU 模块，或需要读/更新 gt5pro-kernel 仓的台账时使用。
---

# GT5 Pro 自编内核 · 接手工作流

## 这个项目的定位（先读这段再动手）

一句话：**做一个"接近原厂行为 + 上游安全修复 + 网络功能可用 + 可验证"的自编内核，不是性能/续航内核。**

- 目标达成度（2026-10-01 **已更正**）：**stable 上游线（6.1.y→188）确实到头了，但 ACK 线从未真正采过**——原"上游已封顶（性能向落地率 0%）"的三条依据（ACK 停更 / erofs·f2fs·mm·sched 落地率 0% / 合高通＝空集）已被推翻，详见 `kernel-kit/更正-上游封顶判断-20261001.md`；**性能与续航不成立且在本机不可证明**——待测效应 ≤1%，而本机噪声带是 I/O **≥20%（实测各档 21%~46%）**、功率 CV 41%，量级差两个数量级（**这条结论被加强，不是被削弱**）。
- 迄今**唯一可归因的实测改善**是内嵌 `regulatory.db` 消掉"固件缺失→内核回退等满 60 秒"那条开机卡点。那是开机时长，不是性能也不是续航。
- 因此：**任何"能省电/能提速"的新改动，先问"效应量能不能盖过本机噪声带"**。盖不过就别做实验，直接记为"理论正向、本机未证"。

## 铁律（违反会丢数据或变砖，逐条有依据）

1. ⛔ **只允许刷 `boot_a`**。永不碰 `init_boot`（root 在里面）、`devinfo`、`abl`、`xbl`、`vbmeta`、`super`、`userdata`。
2. ⛔ **不碰 `boot_b`**。本机是虚 A/B（`ro.virtual_ab.enabled=true`）⇒ 换槽会连 `super` 的另一半旧系统一起起 ⇒ 数据风险。双槽方案已判死。
3. ⛔ **不新增内核导出符号，也不允许导出符号消失**。这是三次砖的机制（见 `references/闸门与判据.md`）。
4. ⭐⭐ **刷前必须过【三道】闸门**。`gate_new_exports.py` 只能抓"符号增减"，
   **抓不到「符号还在、CRC 变了」—— opt15 就是闸门全绿、刷进去 9 个模块挂掉、WiFi/蓝牙全废**；
   而闸门2 又看不见「**符号缺失**」（opt53 的 `oplus_bsp_sched_ext` 缺 7 个符号就是它漏掉的），
   也拦不住 opt51 那种「**493/493 全坏**」的破坏性配置改动。
   ① `tools/gate_new_exports.py` ② `tools/gate_vko_crc.py` ③ **`tools/gate_all_modules.py`（全量厂商模块审计）**。
   **通过标准：闸门1 = 命中厂商 `新增=0` 且 `消失=0`，且 `遮蔽=0`**（导出集差异 ∩ 厂商引用名 = ∅；
   ⚠️ `新增=N 消失=M` 是原始计数，**不要求为 0**；早期文档的"新增=0 消失=0"是过时的严格模式，已作废）；
   **闸门2 = `会拒绝装载的模块 = 0`**（opt49-crc 起蓝牙 `sk_filter_trim_cap` 已定点覆写抹平；更早的版本是 1 = `bluetooth.ko`）；
   **闸门3 = 全量 493 模块审计 `VERDICT: PASS`**（缺失=0 且 CRC 不符=0）；
   其**符号全集 = 三者并集 = 内核导出 ∪ 厂商模块导出 ∪ 外部参考**（opt54 实测 = **21116**）。
5. ⛔ **不魔改 EAS / CPUFreq / cpuidle / 社区调度器**；不做游戏向调优（机主明确不打游戏，要"均衡"）。
6. ⛔ **不提议测/换 zram 算法或换页**——由机主自己的模块控制。
7. ⛔ **不用 SUSFS**；不做 `prjname`/机型伪装去套厂商云控参数（机主已拒，不要重提）。
8. ⛔ **不照抄第三方内核的 config 加项**。实测 cctv18 那份加了 `USER_NS`+`SYSVIPC`
   ⇒ **493 个厂商模块拒载**。「加个 namespace 支持」这种看起来无害的 config 最危险
   （`CONFIG_SYSVIPC` 给 `struct task_struct` 加字段、`CONFIG_USER_NS` 给 `struct cred` 加字段）。
9. ⛔ **中枢结构体禁令**：动 `struct task_struct` / `struct cred` ⇒ 493 个模块拒载；
   动 `struct rq` ⇒ 47 个。**任何 config 或头文件改动都要过闸门，不许凭推理。**
10. ⚠️ **`fastboot flash boot_a` 会顺手把该槽设为 active**（fastboot 33.0.1 帮助原文）⇒ 写完必须立刻 `fastboot set_active a`。
11. ⚠️ **重启/刷机前先问机主**，并确认电量 **≥15%**（机主 2026-10-02 从 30% 下调）。
12. ⚠️ **改设备侧任何文件前先留删前副本**（PC 侧一份 + 设备侧一份），且**别指望设备侧那份活过重装**——KSU 装模块是整目录替换。
13. ⛔ **不要在手机上跑全盘 `grep`**（2026-10-02 踩过：负载飙到 1.7e10、手机卡到要重启）。设备侧搜索一律限定目录。
14. ⛔ **`/proc/cmdline` 含本机序列号与 `oplus.avbkeysha256`**；`rooter-backups/` 含 SN/米家 key/MAC。**整串不得外发**，对外只给单个必要文件。

## 现役状态（2026-10-08 快照，细节见 references/现状与产物.md）

| 项 | 值 |
|---|---|
| 内核 | **`6.1.141-android14-11-o-ltcdz5-v1.1-opt54`** / banner **`#75-ack304-v1.1-opt54`** |
| 归档刷入件 | `images/boot-v1.1-opt54-repacked.img` md5 **`cbd8a8297bc0eca55cc66baba571dba0`**（201,326,592 B） |
| 裸内核 | `Image.opt54` md5 **`bbbc2cc39c5007795796f9ae0abc4d7f`**（39,336,448 B） |
| 源码 | WSL `/home/builder/kwork/cctv18/repo/local/kernel_workspace/common`，**分支 `opt54` / HEAD `77b4ed9d804f2a16a2966b46bb5c8f088b33eb42`**（已推送；tag 于发布时打） |
| 规模 | **4 文件 +50/−8，另新增 1 文件**（新增 `kernel/sched/hmbird_export.c`；改 `kernel/sched/ext.c`、`ext.h`、`kernel/sched/Makefile`、`scripts/setlocalversion`） |
| 回退首选 | **opt53** `images/boot-v1.1-opt53-repacked.img` md5 `f927d8a259f0fad033e6c9b283066ae7`；更早 **opt50** `4a2829cf415756107d3785157e7289cd` |
| AK3 | `images/GT5Pro-RMX3888-v1.1-opt54-AK3.zip` md5 **`e942c4fa81c2f94d411162a51bb8debf`**（含 horae_once / quiet_logs 自动安装） |

> ⛔ **opt54 的 scx 只到「接口出现」**：`/sys/kernel/sched_ext` 已出现、厂商模块 `oplus_bsp_sched_ext.ko` 可装载，
> 但 **`enabled` 实测 = 0，scx 调度类未启用**；**禁止在这台设备上 register 任何 scx 调度器**
> —— opt43 实测整机硬挂死 + PMIC 看门狗复位（见下文「scx（风驰）」一节）。

> 🔴 **权威值只看两处**：`README.md §现役与回退` 与 `CHANGELOG.md §一（发布记录）`。
> 本表是**快照**（2026-10-08），任何文档与本表冲突时以那两处为准。
> ⚠️ 2026-10-04 审计发现本表此前写「现役 opt37 / 回退 opt36」，**落后 10 个版本** —— 已更正。
> ⚠️ 2026-10-08 再次审计：本表此前停在 **opt47**（落后 7 个版本）—— 已更正为 opt54。

> **⚠️ 回退件已压缩（2026-10-03）**：为腾 C 盘，**历史镜像改成 `.img.gz`**（192MB → 约 16MB，12 倍）。
> 保持**未压缩可直接刷**的 = **`boot-version1-opt36` 起、直到现役 `boot-v1.1-opt54` 的全部 `.img`（21 个，
> 含现役 opt54 / 回退首选 opt53 / 更早 opt50）** + `boot_a.img`（原厂，最后防线）+ `init_boot_a.img`（root 备份）。
> 其余 **25 个 `.img.gz`** 刷前必须先解压：
> `wsl -d Ubuntu-24.04 -- bash -lc "gzip -d /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/<名>.img.gz"`
> 详见 `images/README-回退件已压缩.txt`。
>
> **opt37 是什么**：**四项 config 减法**（零代码）——
> ① `CONFIG_UBSAN=y→n`（连带 TRAP/BOUNDS/LOCAL_BOUNDS/SANITIZE_ALL）
> ② `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y→n` ③ `CONFIG_INIT_STACK_ALL_ZERO=y→n`（→`INIT_STACK_NONE=y`）
> ④ `CONFIG_ZRAM_MEMORY_TRACKING=y→n` 与 `CONFIG_RCU_NOCB_CPU_DEFAULT_ALL=y→n`（**这两项真原厂本来就是 n**，是我们多开的）。
> 效应量诚实说：合计 2~8% 但**本机尺子测不出**；⚠️ ①②③ 是"用缓解网换性能"，回退各只需改一行 config。
> Image 从 38,357,504 → **38,095,360 B**（小 256 KB，UBSAN 插桩确实去掉）。
> 详见 `kernel-kit/version1-opt37-四项config减法与olddefconfig禁令-20261003.md`。

> **⚠️ 版本号规范 2026-10-03 已统一**：`…-version<族>-opt<构建序>`，**`p` 字母废弃**。
> 旧写法 `opt15-p32` 今后写 `version1-opt32`；banner 写 `#<序号>-ack<N>-version<族>-opt<构建序>`。
> 详见 `kernel-kit\版本号规范-20261003.md`。本版（version1-opt36）是第一个用新规范的。
>
> **P36 是什么**：`drivers/ufs/` 三处修复 ——
> ① **CVE-2026-43471**：`ufshcd_add_command_trace()` 对会返回 NULL 的
> `ufshcd_mcq_req_to_hwq()` 未判空（同树 `ufs-mcq.c:523` 对同一 helper 是判空的，是最硬内证）；
> ② h8 exit 在 runtime resume 失败时走 link recovery 而非 error handler（上游 `35dabf4503b9`/ACK `565241067e73`）；
> ③ ②的后续重构 `4a07d6ce4683`（**单独打不上，必须成对**）。
> 详见 `kernel-kit\档案/立项与方案/version1-opt36-UFS修复-20261003.md`。
>
> **P35 = version1 起点**：把版本串后缀从 `-opt15` 切到 `-version1-opt35`。
> 改的是 **`scripts/setlocalversion` 末尾那一行硬编码**（`CONFIG_LOCALVERSION` 是空的、
> `LOCALVERSION_AUTO=y`，`kernelrelease` 完全由该脚本决定；厂商把它粗暴改过 —— 真正的
> scm 逻辑后跟 9 行冗余 `sed` 再一行写死 `echo`）。
> 实测：`uname -r` 改了、`lsmod` 仍 621 ⇒ 版本串在 `same_magic()` 里被跳过（有 `__versions` 时），
> 不影响厂商模块 CRC。⛔ 但每次改版本串后仍必须实测 `lsmod` 不减少（opt54 实测 = **628**）。
| KSU 模块（我们的） | `lru_gen_on` **v3**（开机后恢复 MGLRU=Y + min_ttl 1000）、 |
| 闸门（最终，**三关**） | 闸门1 `新增=9 消失=0`、命中厂商 `新增=6 消失=0`、**遮蔽=0** ⇒ **PASS**；闸门2 会拒绝装载 **= 0**；**全量 493 模块审计 PASS**（缺失=0 / CRC不符=0；符号全集 = **21116** = 内核 ∪ 厂商模块 ∪ 外部参考）|
| 刷后基线 | **`lsmod` 628**；`Unknown symbol` **0**；`disagrees` **0**（opt49-crc 起蓝牙 `sk_filter_trim_cap` 已定点覆写抹平）；**真 oops 0**；`Oops/BUG:/Kernel panic` **0**；`pstore` 0；**SSG `[ssg]`**；蓝牙 `state ON`/`crashed 0`；`WARNING` **17 条**（全属厂商模块 modprobe 重复注册）|
| 镜像与模块包 | 逐文件大小 + md5 见 `images/清单.txt` |

⚠️ **⛔ 别刷 `boot-opt15-p13-repacked.img`**：那一版 `/proc/loadavg` 爆到 1.7e10（P16 已修）。
⚠️ **P28 的内容**（相对原厂）= stable 6.1.142~188 的 `.c` + **ACK 四轮收割**（round1 68 / round2 138 /
2 补 6 / round3 48 / round4 164+11，总账 **435 个 ACK 提交**，其中真影响运行内核 **≈409**）
+ **round4 续批**（即"**122 个冲突块**"的人工活，53 文件 +516/−270）
+ 网络功能（BBR/fq/ipset/IPv6 NAT）+ 内嵌 `regulatory.db` + 10 项社区 config + ThinLTO + 减脂（**实际只有 KFENCE 采样一项生效**，UBSAN/INIT_ON_ALLOC 未关、可补回）
+ **SSG 电梯**（`CONFIG_MQ_IOSCHED_SSG`）+ `PANIC_TIMEOUT=30`。
⚠️ **构建走了三轮**（编译错 → 闸门1 FAIL 判砖 → PASS），含两次 **hunk 级**回退；**闸门第 5 次救场**
（`prep_new_page` 导出会翻厂商弱引用）。详见 `references/闸门与判据.md` §构建迭代。
详见 `references/现状与产物.md`、`档案/ACK/ACK第三轮-落地-20261002.md`、`档案/ACK/ACK第四轮-落地与收敛到头-20261002.md`。
⚠️ **自动收割已经到头**：**122 个冲突块已在本轮 P28 做完**；**更早窗口已由 round5 实测确认无货**（2025-12-10..2026-05-20，2787 非 merge → 过滤 386 → 真候选 119，其中全冲突 27、碰 25 个 `.h`、新增 30 个导出，闸门1 必然判砖，且缺前置 config）；剩下的是 8 个碰中枢结构体（闸门封死）+ 依赖缺失 10，**别再自动往下捞**。

## 五个常见任务的操作流程

### A. 出一版新内核并刷入

> ★ **这是固定流程**（2026-10-03 机主确立）：**每版做完刷完 → 派一个子代理去决定"下一版做什么"**，
> 不要 Lead 自己拍脑袋定方向。子代理要拿到：现役状态、本版做了什么、**可达性重判结果**、
> 已勘探过的区域清单、以及"三条判据"。它的输出要能直接变成下一版的施工单。

**第 0 步（固定流程）：派子代理定方向**
- 给它：现役版本/md5、本版改动与**真实可达性**、已勘探区域（别重复）、三条判据、双闸门口径
- 要它给：**明确推荐做什么 + 做到哪一版 + 为什么 + 需要什么前提**
- ⚠️ 子代理的结论**必须自己复核**（今天已有 5 次"代理结论需复核"：SSG 电梯状态、100755 权限、
  `prep_new_page`、MGRL 劣化、HybridSwap 是否编入、ipset 是否被使用）

**第 1 步：选内容 —— 先用【三条判据】筛掉"走不到"的**
判一个缺陷值不值得做，**三条缺一不可**（详见 `references/闸门与判据.md`）：
1. `out/.config` 里那个开关是开的
2. `out/` 下有对应 `.o`（且调用点没被 `#ifdef` 排除）
3. ★ **用户态真的有那个工具、并且真的在用它**（2026-10-03 新增）
   —— 反例：`CONFIG_IP_SET=y` 且编了 117 个 `.o`，但设备上**没有 ipset 工具、slab 里没有
   `ip_set` 对象** ⇒ 针对 ipset 的修复**永远不被触发**。

**第 2 步：改代码 / 改 config**
- ⛔⛔ **绝对不要跑 `make olddefconfig`**（2026-10-03 实测：它做依赖重解析，会静默丢掉
  `COMPAT`/`LTO_CLANG`/`CFI_CLANG`/`SHADOW_CALL_STACK`/`KASAN_HW_TAGS` 等一大批 ——
  **即使带 `LLVM=1` 也丢**。`COMPAT=n` 会让 `task_struct` 等核心结构体尺寸全变 ⇒ 493 模块拒载）。
  ✅ 正确路径：**`make gki_defconfig O=out`**（字面写入，不重解析）；`make Image` 的 `syncconfig` 安全。
  ✅ config 改动**必须同时写** `out/.config` + `arch/arm64/configs/gki_defconfig`（两个真值源）。
  ✅ 用 **`/proc/config.gz`** 验证运行内核真值（`CONFIG_IKCONFIG_PROC=y`，原厂也开）。
- ⛔ **搬补丁必须按【提交日期】排序**，不能按 sha（round 2 按 sha 排造成大量假冲突）。
- ⛔ **成对改动（`.c`+`.h`）必须成对应用或成对放弃**（踩过：只应用 `.c` 半边 ⇒ `/proc/loadavg` 爆表）。
- ⛔ **不要用 `patch -F3`**（会报成功但把 hunk 塞进语义错误的位置）；用零容错 `-F0` + 内容自检。
- ⛔ **改中枢结构体 ⇒ 493 个模块拒载**（`SYSVIPC`/`USER_NS`/`SCHEDSTATS`…），必须过闸门。
- ⛔ **同一文件里两处文本完全相同时，不能用字符串 replace**（按行号 + 断言；踩过 f2fs 340 vs 2316）。
- ⚠️ **`100755` 的源码文件会让补丁打不上**（`has type 100755, expected 100644`），
  但那条**只是 warning** —— 判"补丁打不上"要读**最后一条 `error:`**（通常是 `patch does not apply`）。
- ⛔ **本树源码文件有 281 个是 100755**；⛔ **禁止"只 chmod"**（会打断 `--apply --index/--3way`）。

**第 3 步：编 `Image`**
⚠️ `make Image` **不会刷新 `Module.symvers`**；⚠️ **必须 `export PATH=<clang17 路径>:$PATH`**
（否则用系统 clang18）；⚠️ 若 PC 换过时间，先查 Clock skew，重编到 skew=0。

**第 4 步：过三道闸门**（都必过，见铁律 4）
```
# ★ 先看 CRC 影响面（改结构体/改原型后必做，能一眼看出"名字看不出来的牵连"）
python3 tools/crc_diff.py <旧版 vmlinux.symvers> out/vmlinux.symvers
#   rc=0 零变化 ｜ rc=1 有变化但不涉及厂商引用 ｜ rc=2 有变化且涉及厂商引用（危险）
python3 tools/gate_new_exports.py out/vmlinux.symvers; echo "rc=$?"   # 判据：命中厂商 新增=0 消失=0 遮蔽=0
python3 tools/gate_vko_crc.py out/vmlinux.symvers \
    ../vendor-ko/vendor_dlkm ../vendor-ko/system_dlkm; echo "rc=$?"    # 会拒载=0（opt49-crc 起）
# 闸门3：全量 493 模块审计（缺失 + CRC 不符，必须都为 0）
python3 tools/gate_all_modules.py <内核树> ../vendor-ko/vendor_dlkm ../vendor-ko/system_dlkm; echo "rc=$?"
```
⛔ 调用方必须传参 + 看 rc + `|| exit 1`（旧脚本 `| tail -5` 是空过）。
📌 2026-10-03 闸门第 5 次真救场：我跑 olddefconfig 打掉 `COMPAT` ⇒ 闸门2 报 **493 模块**（全部）。
📌 2026-10-03 闸门第 6 次真救场：`struct nf_conntrack_expect` 加一个字段 ⇒ **109 个导出 CRC 变化**，
   其中 39 个**名字里看不出来**（`__skb_get_hash` 经 `struct sk_buff` 被牵连）⇒ 闸门2 报 **7 个模块**
   拒载，含 **本机 WiFi 驱动 `qca_cld3_kiwi_v2`**。
⚠️ **务必归档每一版的 `vmlinux.symvers`**（`cp out/vmlinux.symvers <归档>/vmlinux.symvers.<版本>`），
   **哪怕这版被闸门拦下、最终没刷** —— 事故版的数据同样有价值（opt39 事故版的 symvers 被后续构建覆盖了，
   只能靠当时的手工比对结论）。
📌 **改结构体的判据（四次实测）**：不是"能不能改"，而是**该结构体在不在任何已导出符号的类型链上**。
   - `struct nf_conntrack_expect`（出现在 25 个已导出原型里）⇒ 109 个 CRC 变化 ⇒ 7 模块拒载 ⇒ ⛔
   - `struct ext4_sb_info`（**ext4 导出 0 个符号**）⇒ CRC 零变化 ⇒ 闸门2 仍 = 1 ⇒ ✅

**第 5 步：出件 + 刷机**
`repack_any.py <裸Image> <输出img> [原厂boot_a.img]` → `tools/verify_image.sh <件>`（**全绿 ≠ 能开机**）。
RAM 引导（`fastboot boot`）**可选**；直接刷也行（电量 ≥15%，**必须 `set_active a`**）。

**第 6 步：上机核验 —— 要查【功能状态】，不只是看有没有报错**
```
lsmod 数量(628) / wlan0 UP / SSG [ssg] / /data f2fs / SELinux Enforcing / MGLRU
pstore=0 / dmesg 真 oops=0 / 蓝牙 dumpsys state ON / ping 通
★ 改过哪条路径，就【功能性地跑一次】那条路径（例：改 ipset 就跑 ipset list/save；
  改 conntrack 就读 /proc/net/nf_conntrack；改 TCP 就 ping + 看连接）
```
⚠️ **`dmesg` 类计数必须【刚开机】采**（晚采会因环形缓冲绕圈得到**假 0**）。
📌 基线（2026-10-03 17:0x）：`WARNING = 10`（proc_register 重名 7 + sysfs 重名 1 + eBPF 提示 1，全属厂商模块）。

**第 7 步：落档 + 提交 + 推送**
台账写进 `kernel-kit/*.md`（**含"哪些修复其实走不到"的诚实结论**）；
skill 若需更新则同步到交接包并**逐文件 md5 校验**；`kernel-kit` 仓提交并 `git push`。

**第 8 步（机主要求，固定流程）：刷机后/收尾时，向机主汇报本轮做了什么**
- 机主原话：**"每次刷机之前告诉我本轮有什么改动 对什么东西有影响"**、**"汇报一下你这几个版本做了什么 这本来是流程规范"**。
- 汇报要包含：版本号与 md5 ｜ 每版改了什么（文件级）｜ 修的是什么（含 CVE/上游 commit）｜
  **影响面与结论（尤其是"哪些其实走不到"）** ｜ 闸门与 CRC 结果 ｜ 回退件。
- ⛔ 禁止只报"做了 4 版"这种无内容的总结；**必须逐版列出可核查的事实**。

**第 9 步（固定流程，机主 2026-10-03 20:49 明令）：★ 方向一律先让子代理评估**
- 机主原话：**"以后方向都让子代理评估，记下来"**；此前也说过 **"接着让子代理决定方向 这是固定流程"**。
- ⇒ **凡涉及"下一步做什么 / 要不要做某件事 / 选哪个方案"，一律先派子代理评估**，Leader 不自决。
- 派评估子代理时必须给它：现役版本与 md5、本版改了什么、**可达性重判结果**、已勘探区域清单、
  三条可达性判据、双闸门口径、**已知被排除/已结案的方向**（避免重复挖）。
- 评估子代理要做**对抗性审核**：找漏洞、推翻假设、或证明不可行——**不是背书**。
- ⛔ 子代理的结论 Leader **必须自己复核**（本轮已多次出现"代理结论需复核"）。
- ⛔ **不要在设备上做可能硬挂死的高危实验**（见下"已结案方向"里 scx 的教训）：
  高危实验前先确认恢复手段（看门狗能复位？pstore 能留现场？ramdump 可用？）。

## ⛔⛔ scx（风驰）：**调度器仍不可 register**（opt43 硬挂死）；opt54 只做到「接口出现 + 模块可装载」

> **2026-10-08 状态更新（opt54，第 4 步达成）**：厂商模块 `oplus_bsp_sched_ext.ko` **已能装载**（`lsmod` 实测 = 1，
> `oplus_bsp_sched_ext 49152 0`），`/sys/kernel/sched_ext` **已出现**（含只读 `enabled = 0` / `switched_all = 0`）。
> **但这只是「可装载 + 不崩」的最小可用面**：`enabled` 实测 = 0，**scx 调度类并未启用**；
> `scx_get_md_info()` 是诚实的空实现（`*vaddr = 0; *size = 0;`）、`task_is_scx()` 恒 false、`iso_masks` 只做保守初始化
> ⇒ **不是** OPPO hmbird 调度器的完整功能（完整功能需 `CONFIG_HMBIRD_SCHED` 底座 + `hmbird_sched_proc_main.c`，本树缺失）。
>
> ⛔ **绝对禁止在这台设备上 register 任何 scx 调度器** —— 见下方 opt42/opt43 两次实测：
> **整机硬挂死 + PMIC 看门狗复位**。opt54 放开的只是「装载」，**没有**放开「启用」。

**结论（2026-10-03 两台实测，仍然有效）**：框架编译完整，但**加载（register）任何 scx 调度器都会硬挂死整机**（无 panic 现场、pstore 0、靠看门狗复位恢复）。

两台实测（都是同一棵树、同一台设备）：
1. **opt42（原厂原样）**加载 scx_example_simple（调了 `scx_bpf_switch_all`）⇒ 硬挂死。
   假设：挂死在"批量切全部任务到 ext 类"。
2. **opt43（我们的实验版）**——注释掉 `ext.c:2840` 的 `scx_switch_all_req = true`（不再强制全接管），
   并重建了**不含 `scx_bpf_switch_all()` 调用**的 BPF 调度器（723,952 B，未定义 kfunc 只剩
   dispatch/dispatch_vtime，本树全有）⇒ **依然硬挂死**（uptime 归零、boot.reason=reboot、pstore 0）。
   ⇒ **"批量切换"假设被证伪**：挂点在 **enable 核心**（审核指向 `ops.init` BPF 调用 :2842、
   或静态位与热插拔交互），不在任务切换。

**为什么原厂是这样**（一树多机 + 拼贴 backport + drop 裁剪 + 这台机器从没启用过 ⇒ 死锁从未暴露）：
- 这棵 `common` 树是 OPPO 系共用；scx backport 是给一加那边"风驰"做的（那些机型 stock 在游戏时启用）
- `scx_bpf_switch_all` 注释是**新 API**（带 `@into_scx`，:3335）但实现是**旧 API**（无参、只能 true，:3341）
- `slim_walt.c` 被删（`ext.c:287` 与 `:2817` 只剩注释残迹）⇒ 利用率反馈没了
- `/sys/kernel/sched_ext`、`scx_bpf_cpuperf_*`、`bpf_iter_num` 全无
  （**其中 `/sys/kernel/sched_ext` 自 opt54 起已由我们补上** —— 出厂内核没有它；另两个仍无）
- git 查证：ext.c 全 refs 仅 2 提交（导入 `a6ad4183cd88` + revert `7a244ff18620`），
  **完整版（含 slim_walt / into_scx 实参）在本仓任何 ref 都不存在**——导入前就被剥离了

**要修好需要**：ramdump/串口 能拿到挂死现场 + 把上游 6.12 的 sched_ext 完整重做（enable 路径 + 利用率反馈 + cpuperf）。
**当前不具备 ramdump ⇒ 结案不做。** 若将来拿到 ramdump，优先看 `scx_ops_enable` 里
`ops.init`(:2842) / 静态位 × 热插拔 这两处。

**第 4 步（opt54）到底做了什么、没做什么**
- **做了什么**：① 新增 `kernel/sched/hmbird_export.c` 导出中心（10 个导出，全部 `EXPORT_SYMBOL_GPL`）；
  ② `__scx_ops_enabled` 由 static key 改成 `atomic_t`（厂商注释要求它定义在 CONFIG_HMBIRD_SCHED 之外；
  这一步同时解决了首版的 `duplicate symbol: __scx_ops_enabled` 链接错误）；③ `ext.c` 末尾注册 `/sys/kernel/sched_ext` kset。
- **没做什么**：**enable 路径一行没动** ⇒ 上面「register 就硬挂死」的结论**一条都没被推翻**。
- ⛔ **内核不得再导出 `get_hmbird_cpu_exclusive`**：它虽在 sched_ext 的缺符号清单里，但**由厂商模块
  `oplus_bsp_game_opt.ko` 自己导出**（readelf 实证 `__ksymtab_gpl_get_hmbird_cpu_exclusive`，实现读它自己的
  `es4g_cpumask_record`，与我们的 `iso_masks` 无关）。内核若也导出同名符号 ⇒ **遮蔽**（闸门1 硬禁止，
  opt6/test_task_ux 的致砖机制）⇒ **不导出**。设备实测：先 `insmod oplus_bsp_game_opt.ko`（modules.load 第 225 行，
  早于 sched_ext 的第 239 行）⇒ sched_ext 的未知符号从 **8 个降到 7 个**。
- 那 7 个符号（`iso_masks`/`ext_module_loaded`/`task_is_scx`/`scx_get_md_info`/`non_ext_task`/`hmbird_dir`/`__scx_ops_enabled`）
  是 **GLOBAL（强）未定义引用，不是 weak** ⇒「内核不导出它 ⇒ 拿 NULL 走跳过分支」这条**不成立**，不导出就**根本装载不了**；
  且**全量 493 个 `.ko` 扫描证明只有 `oplus_bsp_sched_ext.ko` 引用这 7 个名字** ⇒ 导出它们不会翻动别的模块的守卫。

**本机实际在跑的游戏/调度内核组件（全部正常，我们从未动过，也不要动）**：
`mpam_game`（按 PID 分优先级组）、`oplus_bsp_frame_boost`、`oplus_bsp_sched_assist`、
`oplus_network_game_first`、`oplus_bsp_task_sched / qos_sched / schedinfo / sched_penalty`、
`sched_walt` + `cpufreq_uag`（当前 governor 就是 uag）。

## 近几版台账索引（2026-10-08）

| 版本 | 内核改动 | 关键结论 |
|---|---|---|
| v1.0-opt38 | netfilter 4 项（CVE-2026-64189 / 97417 / 31414） | ⚠️ ipset 那两项**本机走不到**（无 ipset 用户态工具） |
| v1.0-opt39 | jbd2 NULL 解引用（CVE-2025-38337）+ ext4 信用额 + i_size 上界 | **首次"CRC 零变化"**；验证纯 `.c` + 只加 inline 的 `.h` 不动 CRC |
| v1.1-opt40 | CVE-2026-31446 ext4 sysfs UAF | **首次通过"改结构体"的闸门**（ext4 导出 0 个符号） |
| v1.1-opt41 | AF_PACKET 时间戳 cmsg 越界读 | `sock_rmem_free` 由 `t`→`T`（生效直接证据） |
| v1.1-opt42 | USB `bRequestType` 位域误判 + LZ4 armv8 `Permtable` 越界读 | 前者 **ADB 自证**；后者反汇编证实；均为 latent→实测 |
| ⛔ v1.1-opt43 | scx enable 实验（注释掉 `scx_switch_all_req`） | **整机硬挂死 + PMIC 复位** ⇒ **scx 调度器禁止 register**（详见上节） |
| ⛔ v1.1-opt44 | gov_override | **未交付**（否证） |
| v1.1-opt45 | 防 sched_ext 硬挂死 + ACK 探针 | 探针版（T0，**非发布**），已被 opt47 取代 |
| ⛔ v1.1-opt46 | BBRv3 移植 | **闸门2 判死**：367/493 个模块会拒载 |
| v1.1-opt47 | ACK 10-02 两条 i2c 修复（注册竞态 / 失败路径补漏） | 已发布（观察期 4.6 h，机主决定提前） |
| v1.1-opt48 | f2fs merged-IPU 补漏 + i2c 注册竞态 + rpmsg UAF + arm64 `VM_FAULT_RETRY_VMA` + pKVM（13 文件 +122/−38） | 闸门1 新增 0 / 消失 0；闸门2 = 1（仅 bluetooth）；未建 Release |
| v1.1-opt49-crc | 蓝牙 `sk_filter_trim_cap` CRC 定点覆写（0x43b2b8f0→0xf5845708） | **首次把闸门2 从 1 压到 0**；`lsmod` 判据 621→**628**；`disagrees` 变真 0；**AK3 自本版起提供** |
| v1.1-opt50 | 5 个 OPPO 厂商钩子回移 + HZ 300→250 + 蓝牙 CRC 重应用 | **`oplus_bsp_game_opt` 由「被拒载」变「可装载」** |
| ⛔ v1.1-opt51 / opt52 | 关 KASAN/KFENCE/DEBUG_LIST/SCHED_DEBUG/SCHEDSTATS/BUG_ON_DATA_CORRUPTION | **否证**：大量模块受影响、`__list_add_valid`/`__list_del_entry_valid` 等关键导出消失 ⇒ 这 6 项被厂商模块锁死在 ABI 上，**不可关** |
| v1.1-opt53 | hmbird/get_util/tick_nohz 五个钩子 + 导出 `__scx_ops_enabled` | sched_ext 缺符号**定案**（真正缺 7 个，不是 19 个；`get_hmbird_cpu_exclusive` 由 game_opt 提供） |
| ★ v1.1-opt54 | **sched_ext/hmbird 私有栈回移**：导出中心 + `__scx_ops_enabled` 去 static-key + `/sys/kernel/sched_ext` kset 注册 | **`oplus_bsp_sched_ext.ko` 可装载 + `/sys/kernel/sched_ext` 出现**；⛔ `enabled`=0，**仍禁 register 任何 scx 调度器** |

详细见 `kernel-kit/` 下各 `vX.X-optNN-上机核验-*.md` 与 `档案/事故与更正/事故-结构体CRC影响面不可穷举-20261003.md`。


### B. 判"某个改动到底进没进这台机器"

- 唯一判据是 **`ar t out/vmlinux.a` 有该成员**，不是 `git diff`、不是 `out/.../<name>.o`。
- ⚠️ `ar` 传绝对路径时成员会打印成全路径 ⇒ 归一化要按 `/out/` 切，切错会得出"0 个进镜像"的假结论。
- 若只是退掉"没进镜像"的文件而代码本身未变：**不用重刷**。证法＝重编后 `System.map` 差 0 行 + 同尺寸 + 字节差仅 32（banner 6 + UTS_VERSION 6 + build-id 20）。

### C. 判"模块件 vs 原厂件"（第三方模块审计）

⛔ **直接读 `/vendor/lib64/...` 会得到假结论**——本机有 22 条 overlay 挂载，读到的是 hybrid_mount 铺的 upper 层，等于拿模块件跟它自己比。
✅ 正确做法：**只读重挂真分区**再比：

```
adb shell su -c 'mkdir -p /dev/tmpv; mount -o ro /dev/block/dm-25 /dev/tmpv -t erofs; md5sum /dev/tmpv/lib64/libgsl.so'
```
（`/vendor` 的块设备从 `/proc/mounts` 现取，别写死。）可执行 `tools/模块件与原厂件比对.sh`。

### D. 改 / 装 KSU 模块

- 只写 per-module 钩子（`post-fs-data.sh` / `service.sh` / `boot-completed.sh`），**不占全局 `/data/adb/*.sh`**。
- 脚本必须 LF（CRLF 会直接打断设备 shell）；`sh -n` 先过；**不要 `while true` 常驻轮询**；不要 `resetprop` 无关项、不要 bind mount、不要碰 SELinux。
- 装：`adb push` 到 `/data/local/tmp` → 设备侧 md5 核对 → `ksud module install <zip>`。⚠️ KSU 只暂存到 `modules_update/`，**必须重启才算装上**；装后核对要读暂存区。
- 停用第三方模块用"关闭"（KSU 开关），**别用"卸载"**——很多模块的 `uninstall.sh` 会全 /data 递归删缓存。

### E. 取基线 / 做对照

- **冷启动计时走 adb**（测的是时间，插线无妨）：`tools/冷启动基线.sh`。
- ⛔ **功耗不许插着 USB 测**：充电分流 + 限亮度/刷新率。功耗只能离机用 Scene 记录器（先充到 ≥40%、锁亮度、10 分钟、导 CSV）。
- ⛔ **别用 `MemAvailable` 快照判"有没有内存压力"**：Android 上可用内存高正是靠回收/换出/杀后台维持的。用累积量：PSI、`pgscan_direct` 占比、`pgmajfault`、`workingset_refault_*`，并按 `/proc/uptime` 换算成每秒。
- 对照实验四条纪律：**判据在看数前写死** / 分母只算"真起来了"的包 / 每轮记起止 uptime / 别让自己的 `force-stop` 污染 `am_kill` 归因。
- ⚠️ 本机杀后台走厂商 `oneclick`（实测 111 条）与 `o-stop`（116 条），**`lmkd` 命中 0** ⇒ "后台留存"这类指标**根本量不到回收类改动**，别拿它当回收改动的判据。

## 沟通与工作纪律（机主明确要求，接手人必须遵守）

- 命令**单行**、标"在哪台机器跑"、不带提示符；高危多步操作给**编号表**（每条标在哪跑＋看到什么算对＋一条总止损），他自己执行。
- 一步的动作别包成多步脚本；长任务让他自己跑并看进度。
- 报错先讲成因再给修法；我给的命令有错就当场认当场换。
- **"测不出收益"是合法结论，要如实报**；不许拿观察硬凑结论，不许拿"我验过了"挡质疑。
- 关键事实必须落文件（本仓 `kernel-kit/`），不能只留在对话里。

## 参考文件（按需读，别一次全读）

| 文件 | 什么时候读 |
|---|---|
| `references/现状与产物.md` | 要版本号/md5/回退链/目录落点时 |
| `references/工具与脚本清单.md` | 找某个脚本干什么用、在哪 |
| `references/环境与通道坑.md` | 命令莫名变空/被截/读不到、WSL 与 adb 出怪问题时 |
| `references/闸门与判据.md` | 动手刷之前、和判断"改动生效了吗"时 |
| `references/已做与已测结论.md` | 有人问"这项目做了什么、有没有用"时 |
| `references/未结案与风险登记.md` | 出现异常（重启、装载失败、功耗异常）先查这里 |

## 权威来源与位置

- **本 skill 的权威副本在 git 仓**：`ltcdz5/gt5pro-kernel-kit` 的 `skills/gt5pro-kernel-handover/`（分支 `master`）。改这里、随仓分发；别人接手＝`git clone` 该仓，把该目录放进自己的 `~/.qoder-cn/skills/`。
- 详细证据与全过程台账在**同仓根目录的 md**（`档案/立项与方案/opt13-减脂版-20260930.md`、`档案/基线与对照/与原厂差异-20260930.md`、`档案/基线与对照/改动总账与正向判定-20261001.md`、`档案/工具方法/root检测面清单-20261001.md`、`留存基线-*` 等）。**本 skill 只写流程与判据，不复制台账**——避免两处说法分叉。
- 机器的桌面工作目录：`C:\Users\USERNAME\Desktop\gt5pro-kernel\`（`README.txt` 是索引；`images/清单.txt` 是所有镜像/包的大小+md5）。
