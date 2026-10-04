<!-- badges -->
[![License](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](LICENSE)
[![Device](https://img.shields.io/badge/Device-Realme%20GT5%20Pro%20(RMX3888)-orange.svg)](https://github.com/ltcdz5/gt5pro-kernel-kit)
[![SoC](https://img.shields.io/badge/SoC-Snapdragon%208%20Gen%203%20(SM8650)-0a7bbb.svg)]()
[![Kernel](https://img.shields.io/badge/Kernel-6.1.141%20OKI-f6a500.svg)]()
[![Status](https://img.shields.io/badge/Status-Open%20Source%20%C2%B7%20Public-3ddc84.svg)]()
[![Build](https://img.shields.io/badge/%E6%9E%84%E5%BB%BA-%E6%9C%AC%E5%9C%B0%EF%BC%88%E6%97%A0%20CI%EF%BC%89-2ea44f.svg)]()

# GT5 Pro 自编内核 · 核件包（kernel-kit）

## 文档地图（顶层只留这些；历史记录全在 档案/）

| 文档 | 用途 |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | **台账（权威）**：§一 发布记录（现役/回退）、§二 全量版本明细、§三 否证与更正 |
| [README.md](README.md) | 本文件：**现役与回退（权威）**、刷写须知、来源标注 |
| [NOTICE.md](NOTICE.md) | 上游归属（GPL 要求，**不得匿名化**） |
| [发布规范-20261004.md](发布规范-20261004.md) | 工作规范：发布前自检、内容边界、评审固化条款 |
| [版本号规范-20261003.md](版本号规范-20261003.md) | 版本串命名规则（`v<族>.<次>-opt<序>`） |
| [路线与边界.md](路线与边界.md) | 可改动面与边界、各方向的取舍结论 |
| [救砖与回退-标准流程-20261001.md](救砖与回退-标准流程-20261001.md) | **砖了怎么办**：退路核验 + 回退命令（时效声明见文首） |
| [新会话开场提示词-交接用-20261004.md](新会话开场提示词-交接用-20261004.md) | **接手入口**：环境、路径、当前状态 |
| [厂商模块导出依赖表-20261003.md](厂商模块导出依赖表-20261003.md) | 数据表：厂商模块导出的 4623 个符号（闸门1 的基准） |
| [README.开源说明-简版.md](README.开源说明-简版.md) | 开源说明（简版） |
| [档案/README.md](档案/README.md) | **历史记录索引**（80 份，按主题分 10 类，含日期与结论摘要） |



> **开源状态**：本仓库以 **GPL-2.0** 开源（见 [`LICENSE`](LICENSE)），全部内容公开可复现。
> **配套内核源码仓库**：[`ltcdz5/gt5pro-kernel-src`](https://github.com/ltcdz5/gt5pro-kernel-src) —— **已发布源码 `v1.1-opt47`**（`main` 与分支 `opt47` = `b195003b`；注释 tag `v1.1-opt47`；逐版补丁见 `history` 分支 `build-history/0034..0038`）
> **版本与发布**：逐版本改动史见 [`CHANGELOG.md`](CHANGELOG.md)；发布节奏（**观察期满一天 + changelog 必须覆盖中间所有版本**）见 [`发布规范-20261004.md`](发布规范-20261004.md)；**正式发布见源码仓库的 [Releases](https://github.com/ltcdz5/gt5pro-kernel-src/releases)**；**逐版真实 diff 见源码仓库 [history 分支的 build-history/](https://github.com/ltcdz5/gt5pro-kernel-src/tree/history/build-history)**

## ⚠️ 开源合规与来源标注（复刻 / 借鉴 / 引用）

本仓库是**复刻/衍生项目**，不是从零原创；内核部分源自厂商开源 + AOSP GKI。**务必遵守各自许可**：

| 层级 | 来源 | 许可 | 说明 |
|---|---|---|---|
| GKI 基底 | **AOSP `kernel/common`**（`android14-6.1`）<br>`android.googlesource.com/kernel/common` | GPL-2.0 | Google 通用内核，本机内核由它 + 厂商改动构成 |
| 厂商源码 | **OPPO/oplus 官方开源** `android_kernel_common_oneplus_sm8650` | GPL-2.0 | 本机的内核源码 drop（*复刻*了本仓库所有补丁的基座） |
| 构建流程参考 | **`cctv18/oppo_oplus_realme_sm8650`** | GPL-2.0 | 同设备家族自动化编译项目，版本命名与流程有*借鉴* |
| Root 方案 | `tiann/KernelSU`、`ReSukiSU/ReSukiSU`、`SukiSU-Ultra/SukiSU-Ultra` | GPL-2.0 | LKM 形式集成 |
| SUSFS | `ShirkNeko/susfs4ksu`、`cctv18/susfs4oki` | GPL-2.0 | 隐藏能力 |
| lz4 1.10.0 / zstd 1.5.7 补丁 | `ferstar`（移植 `Xiaomichael`） | 见上游 | *引用*其内核补丁 |
| 三星 SSG IO 调度器移植 | 社区整理 | GPL-2.0 | *借鉴* |
| 打包工具 | `osm0sis/AnyKernel3`、社区镜像工具（如 `UY-Scuti`） | 各自许可 | *借鉴*思路与布局 |
| BPF 工具链 | 官方 `libbpf/bpftool`（LGPL-2.1 / BSD-2-Clause） | 双许可 | scx 实验用 |
| 调度扩展参考 | **LunarKernel（LSE）** | 见上游 | *借鉴*其 slim_walt 模块化路线 |
| 基带保护（BBG） | **`vc-teahouse/Baseband-guard`** | GPL-2.0 | 以 **git 子模块**引入（`CONFIG_BBG`，`security/baseband-guard/`），阻断对关键分区/设备节点的未授权写入；提交 `a5b57f15d6b5` |

> 逐项完整标注见 **[`NOTICE.md`](NOTICE.md)**。本仓库 `tools/` 下每个脚本头部也标注了作者/许可/借鉴汇总。
> ⚠️ **未包含任何厂商闭源 blob**；对厂商源码的全部修改均以 GPL-2.0 公开。

---
# GT5 Pro 自编内核 · 核件包（kernel-kit）

目标机：**真我 GT5 Pro（pineapple / RMX3888，SM8650）**，Android 16（RUI 7），A/B 槽位
本套件 = 从零复现"自己编一版接近原厂 + 网络/防护增强"内核所需的**全部脚本、配置与坑记录**。
（源码树本身很大，另存；见末尾"源码树"一节）

---

## 0. 一句话流程
```
拉源码树 → 改配置 → 跑 builder（3 分钟出 Image）→ repack_any.py 塞进原厂 boot 布局 → fastboot flash boot_a
```

## 1. 依赖（WSL Ubuntu，仅一次）
- `git wget curl zip patch python3` + 交叉链：`gcc-aarch64-linux-gnu`（`aarch64-linux-gnu-gcc` 13.x）
- 编译器：**AOSP clang r487747c（build 10087095，clang 17.0.2）** —— 与原厂逐字符同款
  - 路径：`~/kwork/kernel_manifest/workspace/toolchains/clang`（也可以直接用系统 clang-18，实测也能编）
- 磁盘 ≥ 60G；16G+ 内存

## 2. 拉源码树（一次性，约 1.7G）
```bash
mkdir -p ~/kwork/cctv18/repo/local/kernel_workspace
cd ~/kwork/cctv18/repo/local/kernel_workspace
# 走 gh-proxy 直连（30MB/s）。官方上游 = OnePlusOSS/android_kernel_common_oneplus_sm8650
git clone --depth=1 https://gh-proxy.com/https://github.com/cctv18/android_kernel_common_oneplus_sm8650 \
  -b oneplus/sm8650_b_16.0.0_oneplus12_6.1.141 common
```
- **这棵树里带 Oplus 私码**（`kernel/oplus_cpu/`、风驰/调度/功耗那批 Kconfig 全在）—— 这是能开机的关键；纯 GKI 树（kernel_common 上游不带绿厂补丁）**编出来开不了机**（挂不上绿厂 f2fs 的 /data，前四版全循环重启的根因）。
- **不用 cctv18 也行**：官方 `OnePlusOSS/android_kernel_common_oneplus_sm8650` 同一分支即可，只是少了 cctv18 的几个修复补丁。

## 3. 我们的配置追加（`my_opts.conf`）
把 `my_opts.conf` 的内容**追加到** `common/arch/arm64/configs/gki_defconfig` 末尾即可（脚本自身也会 append 别的，重复行 Kconfig 取最后一条，无害）。

## 4. 编译
```bash
cd ~/kwork/cctv18/repo
bash local/builder_6.1.141.sh      # 本目录的同名脚本 = 已改成非交互版
```
脚本里已改好的关键点（别改回去）：
| 项 | 值 | 为什么 |
|---|---|---|
| `LLVM=` | `1` | 用 PATH 里的 clang（跳过 llvm.sh/LLVM20 的 1-2G 下载） |
| `CC=` | `ccache clang` | 增量编译，改动重编几十秒 |
| 所有 github 源 | `https://gh-proxy.com/` 前缀 | 直连 30MB/s；**不要设 http_proxy**（Clash 没开就 `Connection refused` 卡死） |
| `SU apt-mark hold firefox` | 注释掉 | 它在 `set -e` 下会直接终结脚本 |
| 克隆 | `[ -d ... ] ||` 保护 | 可重复跑、不重下 1.7G |
| 补丁 | `|| true` | 幂等 |

产物：`local/kernel_workspace/common/out/arch/arm64/boot/Image`（~37MB **裸 Image，不能直接 flash**）

## 5. 重打包 + 刷机
```bash
# 电脑上（Windows Python）
python tools/repack_any.py <裸Image> images/boot-xxx-repacked.img   # 缺省以 images/boot_a.img 为底(保留 AVB0/AVBf、分区大小不变)
adb reboot bootloader
fastboot flash boot_a C:\...\boot-xxx-repacked.img
fastboot reboot
```
- **救砖/回退**：`fastboot flash boot_a boot_a.img`（原厂镜像，**永远留着**）
- boot v4 布局（**大端 AVB**）：`[0:4096]头 | 4096:内核 | 页对齐 | AVB0 vbmeta | … | 末尾-64:AVBf footer`；⛔ 丢 AVB0/AVBf ⇒ 重启直接落 fastboot

## 6. 坑清单（全是血换的）
1. **改版本后缀**必须直接改 `common/scripts/setlocalversion` 最后一行（`echo "-<后缀>"`）；只改脚本里的 `CUSTOM_SUFFIX` 变量会"横幅显示新值、产物仍旧"。
2. **配置静默丢弃三类**：① 符号所在 Kconfig **没被 source**；② `depends on` 没满足；③ 被 `if`/`menuconfig` 总开关包着（如 `CONFIG_DEFAULT_FQ` 需要 `CONFIG_NET_SCH_DEFAULT=y`）。⇒ **编完必须 `./scripts/extract-ikconfig <Image>` 回读**。
3. **范围铁律**：以设备 `/proc/config.gz`（原厂 config）为基准。原厂开的 Oplus 项就那 10 个；原厂没开的不追。
4. **`kernel/oplus_cpu/` 整个目录不参与编译**（全树只有 `kernel/Makefile:142` 引用了它的 `sched/sched_tune/` 一个子目录）⇒ 写在这里面的"省电向"开关**全是空转**：`EAS_OPT`、`TASK_CPUSTATS`、`SUGOV_POWER_EFFIENCY`、`LOADBALANCE`、`SCHED_SPREAD`、`GKI_CPUFREQ_BOUNCING`、`POWER_DIAG` 一律别写。**三重验证法**：① `out/System.map` 找符号 ② `out/**/*.o` 找目标文件 ③ Image 里找字符串——三者都没有 = 没编。这些功能实际由 `vendor_dlkm` 预装的 `.ko`（`oplus_bsp_task_cpustats`/`oplus_bsp_eas_opt`/`oplus_bsp_task_sched`）提供，**原厂 config 里它们全是 not set 也是这个原因**。
5. **厂商模块靠 KMI**：同 KMI 家族（android14-6.1）内换小版本可开机（实证：SpiderDroid 6.1.145 正常启动）；跨大版本（android15-6.1 / 6.6）会撞 ABI ⇒ 开不了机。
6. **`kernel_common` 上游树 ≠ 能开机的树**（缺绿厂 f2fs 等）—— 必须是带 Oplus 私码的那棵。
7. zram 压缩算法由**厂商用户空间**决定（本机默认 `zstdn_o`，厂商模块 `oplus_bsp_zstdn_o`）；系统分区是 **lz4-erofs**（所以 lz4 补丁才是日常收益）；内核自带的 `zstd`/`lz4` 要主动切才会用到。

## 7. "同步上游"这条路走过的全程与结论（2026-09-29，**结论：关闭**）
### ① 换官方分支＝倒退（实测否证，别再试）
`git fetch --depth=1 <OnePlusOSS 的 gh-proxy URL> oneplus/sm8650_b_16.0.0_oneplus12`（tip `ebdd1643c` 2026-09-14）
与我们的基线 `7a244ff18`(cctv18, 2026-07-12) 一比 = **`+466 / −87589`**：
- `kernel/oplus_cpu`、`drivers/soc/oplus/{oplus_resctrl,storage}` 在官方树里**是指向仓外的符号链接**
  （`git ls-tree` 显示 mode `120000`，内容 `../../../vendor/oplus/kernel/cpu`；`kernel/locking/oplus_locking.c`
  官方版只剩 **59 字节**的 symlink，cctv18 版是 **22,922 字节**真源码）⇒ 只 clone 公开仓拿到的是悬空链接。这就是"开源开一半"。
- 官方还**真删**了我们在用的：`tcp_brutal.c`、`net/ipv4/Kconfig −17`、`ssg-*` 调度器、`waker_identify`、`drivers/rekernel`。
- 三棵树 `Makefile` 的 SUBLEVEL **都是 141** ⇒ "官方有 9 月提交" ≠ "有新版可升"。
- cctv18 的价值＝顶端那个 `Revert "Synchronize code…"`（把覆盖式同步撤掉、真源码留在树里），代价＝代码停在 7-12。

### ② 只取"非删除增量"也**刷出循环开机**（三次全灭，控制版证明不是流程问题）
`git diff --diff-filter=d` 挑出 25 文件（+287/−87）、`git apply --check` 干跑全过、`Module.symvers` 逐符号 CRC
对比 **变 0 / 消失 0**、config 与 opt5 逐行相同、regdb 字节指纹命中 —— **全绿，仍循环**：
出 realme logo 后快速复位，且 `/sys/fs/pstore` 全空（连 panic 记录都没留下）。
- **控制实验**：opt5 源码 + 同一套流程（`olddefconfig`+`make Image`）出 `-ctl` 版 ⇒ **正常开机** ⇒ 构建流程无罪。
- **A 组**（5 文件）循环；**A 组去掉唯一有行为的 f2fs** 后（`-a2`）**照样循环** ⇒ 我的"纯声明/导出=无行为"判断被证伪。
  机制线索：`android/abi_gki_aarch64_oplus` 是 **GKI 导出白名单**，往里加 12 行 ⇒ `Module.symvers` **凭空多 18 个符号** ⇒ 清单改动也是行为改动。
- ⛔ **`-a2` 到底为什么循环，我不知道。** 两条解释（f2fs 才有行为 / 导出集变了影响模块加载）都被数据否证。
  ⇒ **静态闸门在这棵树上不覆盖"能不能开机"，所以不许再说"可以直接刷"。** 这条线关闭，以后只按**具体 CVE 单点 backport**（lz4/zstd/CVE-2026-43499 就是这么落地的）。

### ③ 两个构建纪律（血的代价）
- **版本 banner 里 `#` 后面是空的**（`# SMP PREEMPT ` 无构建号无时间戳）⇒ `/proc/version` 唯一可辨识的就是**后缀** ⇒ **每一版必须改 `scripts/setlocalversion` 末行**（opt5=`-ltcdz5`、opt6=`-ltcdz5-up0914`、控制版=`-ctl`、A组=`-a`/`-a2`）。
- **配置基准只能用上一版实测 `.config`**：`cp <上一版>.config out/.config && make … olddefconfig && make … Image`。
  别走 `gki_defconfig`——builder 每轮往它尾部 append 一份自己的块（799→889 行、**31 个键重复**），谁在最后谁生效，会静默改配置。
- **`config_fix` 会让 `/proc/config.gz` 与 `extract-ikconfig` 撒谎**：builder 的 `config.patch` 往 `kernel/Makefile` 注入了
  一段，生成 `config_data` 时把 `CONFIG_IP6_NF_NAT=y` 显示成 `n`。⇒ **判"某配置到底有没有编进去"要看 `out/include/config/auto.conf`
  和生成头 `out/include/config/**/*.h`**，别信 ikconfig（我据此误判过一次"回归"）。
- 切树用 `git checkout -f`（builder 会改 `scripts/setlocalversion`，普通 checkout 会被挡）。

## 8. 本套件包含
- `builder_6.1.141.sh` —— 非交互构建脚本（已按上表改好）
- `my_opts.conf` —— 我们的配置追加（网络 + 防护 + 默认值）
- `repack_any.py` —— boot v4 重打包（保留 AVB）
- `patches/` —— lz4 1.10.0 + zstd 1.5.7、CVE-2026-43499、config.patch 等
- 源码树：另存（1.7G，`git bundle` 见同目录）

## 9. 成品与回退（当前状态）
- **设备现役（已刷）＝`v1.1-opt47`（★已发布 2026-10-04）**：`images/boot-v1.1-opt47-repacked.img`，md5 `4ad29d109c597f018e30f2f908d5031a`（裸核 `f7dcb69f3828a62f95687bc4da262195`）
  含：i2c 适配器注册竞态修复 + 失败路径补拆 IRQ domain（取自 ACK 10-02 两条）+ 上一版 opt45 的「防 sched_ext 硬挂死」
  ⚠️ 观察期起点 **2026-10-04 18:20** ⇒ **10-05 18:20 期满后**才作为交付版发布；`v1.1-opt45` 探针版已被它 supersede（未发布）。
- **上一个候选（已被 supersede）＝`v1.1-opt45`（探针 2）**：`images/boot-v1.1-opt45-p2-repacked.img`，md5 `4edea16d3046577b83dd3c8cf82be154`
  （裸核 md5 `60d964f748c5f1c56750833c6eb2b6ad`；banner `#72-ack304-v1.1-opt45`）
  它只做**一件纯收益的事**：把 `sched_ext_ops` 从 BPF struct_ops 类型表里摘掉 ⇒ **任何 sched_ext 的 BPF 调度器加载都会干净报错，而不是硬挂死整机**
  （此前实测：`bpftool prog loadall` 仅加载就挂 ⇒ uptime 归零 + 看门狗复位）。同版还带一句 `scx_ops_enable()` 早退（实测永远到不了，作第二层）。
  ⚠️ **观察期实际只有 4.6 小时（2026-10-04 18:20 → 22:5x），未满 24 小时 —— 机主明确决定提前发布**；已记录在案并写进 Release 正文。
- **已发布版＝`v1.1-opt42`**：`images/boot-v1.1-opt42-repacked.img`，md5 `4bd362b0a17513474de217ea9beb8ae3`
  （裸核 `perf42/Image.opt42` md5 `2e20e2c1b7dea60cdfee3d58a730a79f`；横幅 `6.1.141-android14-11-o-ltcdz5-v1.1-opt42`）
  含 opt38~opt42 的全部安全修复：ipset dump 竞态、nf_conntrack_expect 空指针解引用、TCP 非对齐读、
  CVE-2026-31446（ext4 sysfs UAF）、CVE-2025-38337（jbd2）、AF_PACKET 时间戳 cmsg 越界、
  USB gadget `bRequestType` 位域误判、LZ4 armv8 Permtable 越界读。
- **回退首选**：`images/boot-v1.1-opt42-repacked.img`（md5 `4bd362b0a17513474de217ea9beb8ae3`，已发布版）；次选 `images/boot-v1.1-opt41-repacked.img`（md5 `8e449caedeb1791923393c9c4eb2245f`）
- ⚠️ **以 `images/` 下的成品为准，别直接刷 `out/`**：`out/` 现为 `v1.1-opt45` 探针 2（与已刷入件同源、可复现）；
  而 **`opt44`（`gov_override`，未采用）与 `opt46`（BBRv3，闸门2 报 367/493 模块会拒载）都绝对不可刷**。
- 历史留档（**都别再刷**）：`boot-v1.1-opt43-repacked.img`（sched_ext/scx 接管实验，实测**硬挂死**，已否证）；
  同步上游线的四次尝试 `boot-opt6-ltcdz5-up0914-repacked.img`、`boot-opt6a-upstream-repacked.img`、
  `boot-opt6a2-upstream-repacked.img` ⇒ **三个全循环开机**；`boot-CONTROL-opt5src-rebuilt-repacked.img`（md5 `d3c206d6…`，
  后缀 `-ctl`，opt5 源码+我的流程）**正常开机**，是那次关键的排除证据。早期成品 `boot-opt5-ltcdz5-repacked.img`
  （md5 `073bfdaa9cbdb7ac67832193eb242f62`，开机 26 秒）同样只作留档。
- 裸内核（**不能直接 flash**）已全部隔离进 `images/不能刷-裸内核/`。
- 原厂底包：`images/boot_a.img`（md5 `a33ff9988e5ffa6a40a13b1c8dad4abb`，**永不删**）；`init_boot_a.img` 不要动（LKM root 在里面）。
- git 锚点：**`v1.1-opt42`=`77aa56a8024c`（已发布）**、`v1.1-opt41`=`e5f8f1aa13a8`（回退次选）、基线 `7a244ff18`(cctv18)；
  开发树：**`opt47`=`5ddf8408`（设备现役·★已发布）**、`opt45`=`6d61a696`（内容已并入 opt47）、`opt46`=`46457461`（BBRv3，⛔ 闸门2 判死）、`v1.1-opt44`=`66b2bf8c`（`gov_override`，未采用）
  ⇒ **`opt43`(scx 硬挂死) / `opt44` / `opt46` 均已否证，勿刷**。
- 配套源码仓库 [`ltcdz5/gt5pro-kernel-src`](https://github.com/ltcdz5/gt5pro-kernel-src)：**`main` 与分支 `opt47` 都是现役源码快照 `b195003b`**（2026-10-04 发布时快进）

## 10. 开机慢：两个**并联**的坑（2026-09-29 全部修掉，87 秒 → 26 秒）
> ⚠️ 两个坑同时在跑，开机时长由更长那头封顶 ⇒ **只修任何一个几乎看不到收益**（实测只修坑1：72821→71383，省 1.4 秒）。
> **别按"各贡献多少秒"相加记账**（净收益 ~62 秒：原厂 74.6s → 12.1s，不是 132 秒）。

### 坑 1（内核侧）：找 WiFi 法规库 `regulatory.db`，ueventd 死等 69~72 秒
**根因**：内核 2.6 秒时请求 `regulatory.db` → 设备上只有厂商格式的 `/odm/etc/wifi/regdb.bin`（格式不同、不能改名顶替）
→ 找不到 ⇒ 走用户态固件回退 ⇒ **等满超时** ⇒ ueventd 被堵 ⇒ 后面整条启动链排队。
**证据**：`dmesg | grep regulatory` ⇒ `ueventd: loading …/regulatory.db took 72017ms`。**原厂日志同样 72017ms** ⇒ 绿厂固件缺文件，不是自编引入的。
**修法（本套件已含）**：`refs/regdb/` 两个文件 → 放 `<树根>/firmware/` → `my_opts.conf` 的 `[opt3]` 段（`CONFIG_EXTRA_FIRMWARE(_DIR)`）
→ 重编。**校验必须用"整文件字节序列"在 Image 里搜**（`img.count(整个文件字节)`），别只看大小或 `grep regulatory.db`（那可能是代码里的字符串常量）。
**关于 `cfg80211: loaded regulatory.db is malformed or signature is missing/invalid`**：**正常、别管**。它走异步回调 `regdb_fw_cb`（`net/wireless/reg.c:1050`）不阻塞；
`iw reg get` 显示 `phy#0 (self-managed)` ⇒ WiFi 法规域由高通驱动用 `regdb.bin` 自管，内核这份本来就用不上；原厂也加载失败、同样 world 域 ⇒ **零功能差异，不值得为签名再编一版**。

### 坑 2（KSU 模块侧）：模块每次开机对 `/data` 全盘递归扫描，堵死 `ksud post-fs-data` 62 秒
**证据**：`dmesg | grep "ksud post-fs-data"` ⇒ `Service 'exec 11 (/data/adb/ksud post-fs-data)' … waiting took 62.068 seconds` ⇒ **与内核无关**。
**定位法**（比读脚本靠谱）：在 KSU 管理器里**禁用**带 `post-fs-data.sh` 的模块（禁用＝`touch /data/adb/modules/<id>/disable`，放开＝`rm -f` 该文件、**必须写字面完整路径**），重启复测；两轮二分锁定。
**元凶**：某第三方 GPU 模块的 `post-fs-data.sh` 结尾"清除 GPU 着色器/图形缓存"段——5 条 `find` 含
`find /data -type f -name '*shader*' -exec rm -f {} \;`（整棵 /data 递归）。**只读探针实测单条 `time find /data -type f` = 40.9 秒**。
⚠️ 曾误判为"91 条 `resetprop` 拖 62 秒"——修好后 91 条照跑、`ksud` 只用 2.471 秒，即已否证。
**修好的读数**：`ksud` 62.068→**2.471s**；`boot_progress_start` 71383→**12090**；`enable_screen` ~87000→**25685**；全日志最慢 `took` 只剩 **96ms**。

## 11. 第三方模块属性表的「效能审计法」（可复用）

> 对第三方模块件的处理细节（原包、清理件、其内部清单与数值）**已按内容边界移出公开仓库**（见本地归档）。
> 本节只保留**可复用的方法与判据**。

**判定准则：别读注释，查有没有人读这个属性名。**
1. 把脚本里的属性名抽成清单（**必须 LF**！Windows 下 Python 文本模式写出每条带 `\r` ⇒ `grep -f` **静默零命中且退出码 0**，踩过）
2. `su -c 'grep -rHaaoF -f /data/local/tmp/names.txt /system /vendor /apex /product /system_ext /odm | sort -u'`（toybox `grep -a` 能扫二进制）
3. **正对照**：同法要能搜到 SF 的 `debug.sf.*`、libhwui 的 `debug.hwui.renderer`，否则"0 命中"不可信
4. 模块自带 `.so` 单独搜——它声称调的就是自己带的驱动，读者最该出现在那里
**实测结论（对某第三方 GPU 模块的属性表）**：它声明的属性名**绝大多数全系统查无读者**；扣掉解锁伪装类与 trace 开关后，真"性能向且被读"的只剩很小的个位数比例。其 `service.sh` 里若干"调优"（脏页阈值、I/O 电梯）**未落地**，一个 `while true` 因漏左括号成了前台死循环，于是它宣称的"定期 fstrim"是**执行不到的死代码**。**唯一实测真落地的只有 `system.prop` 的 resetprop**。
⛔ 判定边界：搜不到字符串 ≠ 数学上无人读（可拼接绕过）；对整段照抄的属性表够用，但别写成 100%。
⛔ **27 条 `persist.*` 清不掉**：已落进 `/data/property/persistent_properties`，`resetprop --delete` 只清内存不改写该文件 ⇒ 重启会带着旧值回来。
属"看得到、没人读、零作用"的空壳；硬抹要触发属性服务整体重写＝动系统属性服务，**不做**。

## 12. 自编内核与真我原厂的"模块差集"（2026-09-29 取证，结论：**不修**）
**量化**：`dmesg | grep -cE "disagrees about version|Unknown symbol"` ⇒ 原厂 **0** 条、opt5 **约 30** 条。
**差集**（两份开机日志的 modprobe 成功清单相减，口径一致）：原厂 55 成/0 败，opt5 48 成/7 败，缺的正好蓝牙一族：
`bluetooth.ko btbcm.ko btqca.ko btsdio.ko hci_uart.ko hidp.ko rfcomm.ko`（在 `/system_dlkm/lib/modules/<真我原厂版本>/` 下）。
另 `oplus_bsp_game_opt.ko` 缺 4 个 `__tracepoint_android_vh_scx_*` —— **他不救（gameopt＝负优化）**。

**为什么"失败"≠"坏了"**：这台机器的蓝牙**不走内核 AF_BT 栈**，走厂商用户态栈（`btpower`+`bt_fm_slim`+QTI HAL）。
实测：opt5 上耳机能连、`dumpsys bluetooth_manager` 里 `A2dpStateMachine state=Connected`；而 `ls /sys/class/bluetooth`、
`/proc/net/bluetooth`、`/sys/module/bluetooth` **全都不存在**。⇒ **千万别再塞一套内核蓝牙进去（两套 HCI 打架，风险实、收益零）**。
残留真实损失只有 `rfcomm`（SPP 串口类）；`hidp`（键鼠/手柄）**不受影响**（`CONFIG_UHID=y`、`/dev/uhid` 在）；PAN 不算损失（`CONFIG_BT_BNEP` 本来没开）。
**根因，别再走回头路**：真我原厂用的是 **realme 自己的 common 树**（证据：`CONFIG_SCHED_CLASS_EXT` 在原厂 config 里连符号都没有、
`CONFIG_HMBIRD_SCHED` 原厂=y 我们没有）⇒ **跨树凑 CRC 是死路**，自编那 7 个 .ko 也只是塞回没人用的栈（`out/` 里现成有，别做）。
**判据教训**：模块清单只能回答"缺了什么"，**不能回答"坏没坏"**；后者只有功能面证据（状态机/实际连接/实测）算数。


## 13. 存储/UFS 这条线的台账（2026-09-29 查完，结论：不动手）
- **配置层与原厂一致**：按 `UFS/SCSI/BLK/IOSCHED/F2FS/INLINE_ENCRYPT` 关键词逐条比 `stock_config.gz` vs 我们的 `out/.config`，
  差异仅 1 条且等价（`CONFIG_MQ_IOSCHED_SSG` 原厂无此符号、我们 =n）。BFQ/deadline/kyber 都在；f2fs 压缩全家桶都在；
  `BLK_INLINE_ENCRYPTION=y`+`FALLBACK=y`、`ufs_qcom` 报 **ICE v4.0.2**、**MCQ nr_queues=9/queue_depth=64/ESI** —— 原厂与 opt5 逐条相同。
- **"三星闪存优化"没有料**：扫 `gregkh/linux` 的 `linux-6.1.y` 上最近 25 条 `drivers/ufs` 提交，**没有一条是三星颗粒的 quirk**
  （都是 Intel pci / mediatek / exynos 主机侧 + 核心错误处理）。控制器 glue `ufs_qcom.ko` 在 vendor_dlkm，**不在我们镜像里**，够不到。
- **缺这 5 条核心修复**（判定法：`git apply -R --check` 能反摘 = 已合入；正着能套 = 缺失）：
  `776ad090f` UIC done completion 初始化（可干净套）、`4a07d6ce4` hibern8 退出失败改走 wl_resume 链路恢复（上下文冲突）、
  `4bf9c3a7a` W-LUN resume 后 EH 失败（可干净套）、`843c13760` `ufshcd_read_string_desc` 缓冲重复（可干净套）、
  `d06eb2620` init 错误路径 use-after-free（上下文冲突）。补丁已存 `patches/ufs-upstream/`。
- **为什么不补**：两份完整开机日志（原厂 / opt5）里 UFS 相关 28 行**逐条一致**，且**零条** hibern8/link-recovery/link-startup 错误
  ⇒ 这些是错误路径补丁，**本机没有触发条件**，补了无感、却要占一次刷机验证（今天已证明静态闸门不覆盖运行时）。
- ⭐ **顺带记一个有意思的事实**：`init.qcom.rc:101` 的 `write /sys/bus/platform/devices/1d84000.ufshc/clkscale_enable 0`
  在**原厂和 opt5 上都失败**（`Permission denied`）⇒ 厂商想关 UFS 时钟缩放没关掉，实际是开着的。这是厂商侧 SELinux 问题，不是我们的损失。

## 14. opt7-clean：把"不干净"的三处清掉（2026-09-29）
**动机**：opt5 功能上没问题，但有三处会让**审计**出错（今天就是被第 1 项骗过一次，误判成"配置回归"）。

**改了什么（只这三样）**
1. **删掉 `kernel/Makefile` 里的 `config_fix`**（builder 的 `config.patch` 注入的）：它在生成 `config_data` 时把
   `CONFIG_IP6_NF_NAT=y` 改写成 `n` 显示 ⇒ `/proc/config.gz` 与 `extract-ikconfig` **谎报**。还原成上游那四行
   （`filechk_cat = cat $<` / `$(obj)/config_data: $(KCONFIG_CONFIG) FORCE` / `$(call filechk,cat)`），不碰 `.config`/`auto.conf`。
2. **`gki_defconfig` 去重**：859 行 → **826 行、重复键 0**（原先 31 个键重复，取值不一致的只有 `HEADERS_INSTALL`）。
   去重时**每个键的取值一律以 opt5 实测 `.config` 为准**，所以生成的 `.config` 与 opt5 **逐行一致**。
3. **清工作区**：builder 每轮生成的 `config.patch.N` / `cve-*.patch.N` 未跟踪垃圾删掉（`git status --porcelain` 里 `??` = 0）。

**故意没做的两件事**：① 不把 `CONFIG_HEADERS_INSTALL` 对齐原厂（它是给工具链导出 uapi 头用的、对手机零意义，
一改 `.config` 就变 ⇒ 全量重编 + 制造"与现役不一致"，违反今天学到的纪律）；② 不动 `69_hide_stuff.patch`（SUSFS）——
它**从来没被应用**（全树 `susfs` 命中 0、Image 内 0），已改名 `未使用-69_hide_stuff.patch` 避免误会。

**闸门实测**：clang 17.0.2 ✓｜后缀 `-clean` ✓｜**`IP6_NF_NAT` 在 Image 内嵌 config 里已回到 `=y`**（这就是谎报消失的正证）✓｜
`out/.config` 与 opt5 差异 **0 行** ✓｜`System.map` 行数 **115,296 = 115,296** 一致 ✓｜regdb 整文件字节 1/1 ✓｜
死开关 2/2 not set、内置 KSU 0、SUSFS 0 ✓。
⚠️ **撤回一条我上一轮说错的话**：`Module.symvers` 比基线"多 19 行"**不是内核多导出了符号**（那些 `__tracepoint_android_vh_*`
在两份 `System.map` 里都是 **0 次**、根本不在镜像里），是 builder 的 `make all` 与我 `make Image` 在 symvers **记账口径**上的差异。
⇒ 连带说明：我用"+19 符号"解释 `-a2` 为何砖机的那条推论**不成立、已撤回**；`-a2` 为什么循环仍然是未知。

**产物**：`images/boot-opt7-clean-repacked.img`，md5 **`c27db830647d82f03c003e9bc865cc14`**，201,326,592 B，版本串 `…-ltcdz5-clean`；git 分支 `opt7-clean`。
**装后自证"干净"的判据**：`zcat /proc/config.gz | grep IP6_NF_NAT` 应显示 **`=y`**（opt5 上显示的是假的 `n`）。
**回退**：`fastboot flash boot_a images/boot-opt5-ltcdz5-repacked.img`（md5 `073bfdaa…`）。

## 15. 刷前闸门套件 `verify_image.sh`（2026-09-29，含阴性对照）
```bash
# WSL 里跑（TREE 默认指向本地内核树）
bash kernel-kit/verify_image.sh <裸Image 或 repacked.img> [基线目录=~/opt5-baseline] [显示名]
```
21 项检查：版本后缀可辨识 / clang 17.0.2 / 8 个特性在位 / regdb 声明 + **整文件字节指纹** / 无内置 KSU /
无 SUSFS / 死开关未混入 / `IP6_NF_NAT` **双口径**（Image 内嵌 vs `out/include/config/auto.conf`，专抓 `config_fix` 谎报）/
`gki_defconfig` 重复键 / `System.map` 行数对基线 / `Module.symvers` CRC 对基线。自动识别 boot v4 与裸 Image。

**自验（用已知答案的样本）**：opt7-clean = **21 PASS / 0 FAIL**；opt5 = **20 PASS / 1 FAIL**，且那唯一 FAIL 正是
`config_fix` 谎报 ⇒ 检测本身有效。

⛔ **阴性对照（最重要的一条纪律）**：`-ctl`（能开机）与 `opt6`/`-a`/`-a2`（三个全循环开机）**闸门读数完全相同**。
⇒ **这套闸门只能挡"构建/内容层"的错，对"能不能开机"零区分能力。**
**任何"全绿所以我可以直接刷"的说法都不成立**；运行时正确性只认刷机，而刷机就要预备回退（现役回退包＝opt5）。
`Module.symvers` 的"多/少 N 行"尤其只作线索：它是 `make all` 与 `make Image` 的记账口径差异，
真实符号要看 `System.map`（今天据此撤回过一次错误结论）。
  档案/基线与对照/与原厂差异-20260930.md ← opt10 vs 真我原厂：源码34文件/config 81项(36有意+45天然)/够不到的5项/功能差集
