<!-- badges -->
[![License](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](LICENSE)
[![Device](https://img.shields.io/badge/Device-Realme%20GT5%20Pro%20(RMX3888)-orange.svg)]()
[![SoC](https://img.shields.io/badge/SoC-Snapdragon%208%20Gen%203%20(SM8650)-0a7bbb.svg)]()
[![Kernel](https://img.shields.io/badge/Kernel-6.1.141%20OKI-f6a500.svg)]()
[![AK3](https://img.shields.io/badge/AnyKernel3-Ready-3ddc84.svg)]()
[![Source](https://img.shields.io/badge/%E6%BA%90%E7%A0%81%E5%BF%AB%E7%85%A7-gt5pro--kernel--src-2ea44f.svg)](https://github.com/ltcdz5/gt5pro-kernel-src)

# GT5 Pro 自编内核 · 核件包（kernel-kit）

> 真我 GT5 Pro（RMX3888 / SM8650 / 6.1.141 OKI）自编内核的**工具、台账与验证件**仓库。
> 源码本体在 [gt5pro-kernel-src](https://github.com/ltcdz5/gt5pro-kernel-src)；本仓库负责“怎么编、怎么验、怎么发布、怎么回退”。

## 现役与回退

| 项 | 值 |
|---|---|
| 现役版本 | `6.1.141-android14-11-o-ltcdz5-v1.1-opt49`（蓝牙修复版）|
| 现役镜像 | `boot-v1.1-opt49-crc-repacked.img`，md5 `c40ee988904f2ea29720b0100b0ad124` |
| **AK3** | `GT5Pro-RMX3888-v1.1-opt49-crc-AK3.zip`，md5 `13966f4df5e14c6289b4aff60b4380d9`（内含附加模块自动安装）|
| 回退首选 | `boot-v1.1-opt49-repacked.img`（md5 `f285f54b2af95af56677d96f96f1b377`）|
| 台账（权威） | [CHANGELOG.md](CHANGELOG.md) §一 发布记录 |

## 快速开始

**刷机（推荐 AK3）**：把 `GT5Pro-RMX3888-v1.1-opt49-crc-AK3.zip` 丢进 KernelSU/Magisk 管理器刷入 ——
自动刷内核 + 自动安装附加模块（`horae_once`、`quiet_logs`）✓

**刷机（fastboot，只刷 boot_a）**：
```sh
fastboot flash boot_a boot-v1.1-opt49-crc-repacked.img
fastboot set_active a        # 必须！fastboot flash 会切槽
fastboot reboot
```

**构建**：见 [builder_6.1.141.sh](builder_6.1.141.sh) 与 [新会话开场提示词-交接用-20261004.md](新会话开场提示词-交接用-20261004.md)
```sh
make -j$(nproc) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
  CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error gki_defconfig all
# 构建后必须执行（否则厂商蓝牙模块因 CRC 不符被拒载）：
python tools/patch_crc_sk_filter_trim_cap.py <Image> <vmlinux.symvers>
```

## 文档地图（顶层只留这些；历史记录全在 `档案/`）

| 文档 | 用途 |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | **台账（权威）**：§一 发布记录（现役/回退）、§二 全量版本明细、§三 否证与更正 |
| [README.md](README.md) | 本文件：**现役与回退（权威）**、刷写须知、来源标注 |
| [NOTICE.md](NOTICE.md) | 上游归属（GPL 要求，**不得匿名化**）|
| [发布规范-20261004.md](发布规范-20261004.md) | 工作规范：发布前自检、内容边界、评审固化条款 |
| [版本号规范-20261003.md](版本号规范-20261003.md) | 版本串命名规则（`v<族>.<次>-opt<序>`）|
| [路线与边界.md](路线与边界.md) | 可改动面与边界、各方向的取舍结论 |
| [救砖与回退-标准流程-20261001.md](救砖与回退-标准流程-20261001.md) | **砖了怎么办**：退路核验 + 回退命令 |
| [新会话开场提示词-交接用-20261004.md](新会话开场提示词-交接用-20261004.md) | **接手入口**：环境、路径、当前状态 |
| [厂商模块导出依赖表-20261003.md](厂商模块导出依赖表-20261003.md) | 数据表：厂商模块导出的 4623 个符号（闸门1 基准）|
| [README.开源说明-简版.md](README.开源说明-简版.md) | 开源说明（简版）|

## 工具（`tools/`，节选）

| 工具 | 用途 |
|---|---|
| `gate_new_exports.py` | **闸门1**：内核导出对账（新增 / 消失 / 遮蔽三侧；需在 WSL 内跑，基准在 `/home/builder/abi/`）|
| `gate_vko_crc.py` | **闸门2**：厂商 .ko 的 modversions CRC 对账（判“会拒绝装载的模块”）|
| `gate_all_modules.py` | **全量模块审计**：逐厂商 .ko 同时报「符号缺失 + CRC 不符」（闸门2 对「符号缺失」是盲区）；`python3 tools/gate_all_modules.py <内核树> <厂商.ko目录...>` |
| `gate0_type_diff.py` | **闸门0**：类型级 ABI 预检 |
| `patch_crc_sk_filter_trim_cap.py` | **蓝牙修复**：把 `sk_filter_trim_cap` 的 CRC 定点对齐厂商期望值（0x43b2b8f0 → 0xf5845708）|
| `preflight.ps1 -Ver v1.1-optNN` | 发布前一键自检（树状态 / 闸门 / 镜像 md5 / 文档一致性 …）|
| `repack_any.py` | 把裸 `Image` 塞进原厂 `boot_a.img` 的 v4 布局 |
| `btf_from_image3.sh` / `btf_full_diff.sh` | 从 Image 抠 BTF 并做类型级对比（排查 ABI 漂移）|

## 归属与免责

- 许可 **GPL-2.0**；内核源码版权归 kernel.org / Qualcomm / OPPO-realme 开源所有
- AnyKernel3 模板：**osm0sis** @ xda-developers；社区参考项目：**cctv18**/oppo_oplus_realme_sm8650、OnePlusOSS/android_kernel_oneplus_sm8650、LineageOS
- 刷机有风险，**责任自负**；本仓库为个人自用与学习用途。

*最近更新：2026-10-08*
