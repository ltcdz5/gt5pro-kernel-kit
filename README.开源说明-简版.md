# gt5pro-kernel-kit — Realme GT5 Pro 自编内核工具与台账包

本仓库是 **Realme GT5 Pro（RMX3888 / SM8650 / pineapple / Android 16 原生 ColorOS）**
自编内核（基于 OPPO 官方 6.1.141 OKI 源码）的**配套工具链、闸门与完整工作台账**。

## 这是什么
- **内核侧**在独立仓库 `gt5pro-kernel-src`；本仓库放**工具、流程规范与决策台账**。
- **只刷 `boot_a`**（永不触碰 `init_boot` / `devinfo` / `abl` / `xbl` / `vbmeta` / `super` / `userdata` / `boot_b`），
  `fastboot flash` 后**必须** `set_active a`。

## 核心工具（`tools/`）
| 工具 | 作用 |
|---|---|
| `gate_new_exports.py` | **闸门1**：新增导出符号与厂商 `.ko` 引用集求交 ⇒ 命中即为砖闸 |
| `gate_vko_crc.py` | **闸门2**：493 个厂商 `.ko` 的 `__versions` CRC 与 `vmlinux.symvers` 对账 |
| `crc_diff.py` | 两版 `symvers` 的 CRC 差异三分法（0 变化 / 变了但厂商不引用 / 变了且厂商引用） |
| `repack_any.py` | 把裸 `Image` 重打包成可刷的 `boot` 镜像 |
| `gate_crc_drift.py` | CRC 漂移监控 |

## 关键结论（血泪换来的，直接看这两条）
1. **`modversions` CRC 闸门**：`CONFIG_MODVERSIONS=y` 下 `same_magic()` 会跳过版本串，
   **vermagic 字符串被忽略，只有逐符号 CRC 才算数**。改导出符号/结构体可能连锁改动大量 CRC ⇒ 厂商 `.ko` 拒绝装载。
2. **改结构体的影响面不可穷举**：`struct nf_conntrack_expect` 加一个字段 ⇒ 109 个 CRC 变化
   （39 个按名字看不出来）⇒ 闸门2 从 1 个涨到 7 个（含 WiFi 驱动）⇒ **砖**。
   而 `struct ext4_sb_info` 加字段 ⇒ **0 个 CRC 变化**（ext4 不导出符号）。
   判据是"该结构体是否出现在任何导出符号的类型链里"。

## 许可与来源
- 本仓库自有内容以 **GPL-2.0** 发布（见 `LICENSE`）；
- 内核源码部分基于 **AOSP kernel/common** 与 **OPPO 官方开源**（均 GPL-2.0）；
- 第三方组件与借鉴来源逐项标注于 **`NOTICE.md`**。

## 免责声明
仅供研究与个人设备实验。刷机有风险（可能不开机、丢数据、失去保修），风险自负。
