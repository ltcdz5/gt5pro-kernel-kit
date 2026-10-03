# 第三方来源与借鉴标注（NOTICE）

本仓库为 **Realme GT5 Pro (RMX3888) 自编内核的配套工具与台账包**，除自有内容外，
包含或借鉴了以下上游/第三方项目。**各部分的版权与许可归原作者所有，均按其原许可使用**。

## 一、本仓库自有内容
- 全部 `.md` 台账/文档、`tools/` 下的闸门与打包脚本（`gate_new_exports.py`、`gate_vko_crc.py`、
  `crc_diff.py`、`gate_crc_drift.py`、`repack_any.py`、`刷opt15.ps1`、`images_出清单.sh` 等）、
  工作流规范（`SKILL.md`）—— 作者 ltcdz5，以 **GPL-2.0** 发布（见 `LICENSE`）。

## 二、内核源码（对应仓库 `gt5pro-kernel-src`）
- 上游基底：**AOSP `kernel/common`**（`android14-6.1` GKI，GPL-2.0）
  —— `https://android.googlesource.com/kernel/common`（镜像 `github.com/aosp-mirror/kernel_common`）
- 厂商源码：**OPPO/oplus 官方开源** `android_kernel_common_oneplus_sm8650`（GPL-2.0）
  —— 本机内核树即基于该 drop；本项目所有补丁均在其之上，遵守 GPL-2.0 提供源码。
- 版本命名与构建脚本参考社区项目 **cctv18/oppo_oplus_realme_sm8650**（作者 cctv18，GPL-2.0）。

## 三、工具链与补丁借鉴
| 内容 | 来源 | 许可/说明 |
|---|---|---|
| Root 方案（KernelSU LKM） | `tiann/KernelSU`、`ReSukiSU/ReSukiSU`、`SukiSU-Ultra/SukiSU-Ultra` | GPL-2.0 |
| SUSFS 隐藏 | `ShirkNeko/susfs4ksu`、`cctv18/susfs4oki` | GPL-2.0 |
| lz4 1.10.0 / zstd 1.5.7 内核补丁 | `ferstar`（移植 `Xiaomichael`） | 见上游 |
| 三星 SSG IO 调度器移植 | 社区（cctv18 项目整理） | GPL-2.0 |
| AnyKernel3（打包） | `osm0sis/AnyKernel3` | GPL-2.0 |
| 镜像打包/解包工具 | 参考 `UY-Scuti` 等社区工具 | 按其原许可 |
| BPF/scx 实验工具链 | 官方 `libbpf/bpftool`（LGPL-2.1/BSD-2-Clause 双许可）、`sched-ext/scx` 样例 | 按上游许可 |
| 风驰/LSE 参考 | **LunarKernel**（LSE，slim_walt 模块化路线） | 见上游 |

## 四、免责声明
本仓库内容仅供**研究与个人设备实验**使用。刷写自编内核可能导致设备无法开机、数据丢失或失去保修，
风险自负。所有对厂商源码的修改均以 GPL-2.0 开放，未包含任何厂商闭源 blob。
