# gt5pro-kernel-kit · 自编内核工具箱与台账

**一句话**：改内核最怕把厂商模块搞崩 —— 这个仓库把「有没有搞崩」变成几个能跑出来的数字，并把每一步记下来。

> 作者：**github@ltcdz5** ／ **酷安@天玑1100逆天功耗** ｜ 由 DeepSeek 协助整理

## 方向状态（2026-10-17）

| 方向 | 状态 |
|---|---|
| **第一条**：风驰游戏切换（进游戏切厂商 `scx` 调速器、退出回 `uag`） | ✅ **在维护** |
| **第二条**：内核态 hmbird 调度类 / 风驰游戏调度 | ⏸ **自 2026-10-17 暂缓**（放弃原因：**工程量大、难度高**）|

- 第二条的收尾结论、真实对局数据与全部实测证据：
  `gt5pro-hmbird/docs/opt163-opt172-收尾结论与暂缓-20261017.md`
- 台账：本仓 `CHANGELOG.md` 第「三十四」章（P0 判决）与第「三十六」章（收尾轮）
- ★核心症结未解★：hmbird 在线时 **cpu5/6/7 被排除出调度视野**，连显式 `sched_setaffinity` 都绕不过。

## ★出片链路（按顺序；漏一步就会得到"构建正常、厂商模块静默拒载"的坏件）★

1. **编内核** —— config 一律以**上一版实测 `out/.config`** 走 `olddefconfig`（不要信会被构建脚本反复 append 的 defconfig）。
2. ★**CRC 定点覆写**★
   ```bash
   python3 tools/patch_crc_targeted.py <Image> <vmlinux.symvers>
   ```
   `genksyms` 对具名结构体变量只哈希类型名 ⇒ `iso_masks` / `task_is_scx` / `sk_filter_trim_cap`
   三个符号**必须定点覆写**成厂商 `.ko` 的 `__versions` 期望值。
   ★**漏跑时构建 `rc=0`、无任何报错，唯一症状是设备侧 `oplus_bsp_sched_ext.ko` 静默拒载（`scx` 消失）。**★
   出片一律用覆写后的 `Image.crc` —— 它比 `Image.pre` **恰好多差 12 字节 = 3 个 CRC 槽位**。
3. **四道 CRC 门禁**，全 `exit=0` 才算过：
   `patch_crc_targeted_v2.py` → `gate_crc_v2.sh` → `gate_crc_diff5.sh` → `gate_crc_pre.py`
   （★`gate_crc_pre.py` 必须用 `python3` 调★；背景与槽位见 `档案/闸门与ABI/`）
4. **三道 ABI 闸 + 刷前闸**（见下）。
5. `python3 repack_any.py <裸Image> <输出img>` 出件。

## 三道 ABI 闸（每次出片后必跑）

| 关卡 | 看什么 | 基准现状（基于 **493 个**厂商 `.ko`）|
|---|---|---|
| `tools/gate_all_modules.py` | 每个厂商模块需要的符号是否都满足 | **缺失 0 / CRC 不符 0**（493/493 可装载）|
| `tools/gate_new_exports.py` | 新增导出有没有遮蔽厂商同名符号 | **遮蔽 0**（另判"新增/消失"两侧）|
| `tools/gate_vko_crc.py` | 有没有模块因版本变化被拒载 | **拒载 0** |
| `verify_image.sh` | 构建 / 配置 / 内容层 | **PASS=20 FAIL=0**（★全绿 ≠ 能开机★）|

★**判据基准**★：一律用 `gateNNN/vmlinux.symvers` 这类**按版快照**
（例如 `gate168/` = 现役 `opt168` 的导出表，版本串与器件 `uname` 对得上）；
★**不要**用 `out-core/`★ —— 那是脏构建目录（`Module.symvers` 与 `vmlinux.symvers` 互相矛盾）。

## 目录速览

| 目录 | 内容 |
|---|---|
| `tools/` | 关卡脚本、CRC 定点覆写、镜像校验、重打包 |
| `模块/fengchi-boot/` | 风驰自启模块的源码 |
| `档案/` | 过程档案：闸门与 ABI、事故与更正、性能功耗、hmbird 二分与方向纠正等 |
| `configs/` 、 `refs/` | 构建配置与基线参考数据（含 622 模块导出基准）|
| `archive/` | 归档（不再使用但保留可追溯）|
| `CHANGELOG.md` | 每一步做了什么、数字多少、结论如何 |
| `发布规范-20261004.md` | 发布纪律：★观察期未满 24h 不许建 Release / 不许宣告发布★；镜像不入公开仓 |

## 常用命令

```bash
bash builder_6.1.141.sh                                    # 构建（工具链路径按本机调整）
python3 tools/patch_crc_targeted.py Image vmlinux.symvers  # ★CRC 定点覆写（漏跑=静默拒载）★
python3 tools/gate_all_modules.py <内核树> <厂商.ko目录...>  # 闸一：厂商模块审计
python3 tools/gate_new_exports.py <vmlinux.symvers>        # 闸二：新增/消失/遮蔽
python3 tools/gate_vko_crc.py <vmlinux.symvers> <厂商.ko目录...>  # 闸三：拒载
bash verify_image.sh <件>                                  # 刷前闸
python3 repack_any.py <裸Image> <输出img>                   # 生成刷机包
```

## 风驰是怎么跑起来的（一句话）

**内核提供风驰要用的 `scx` 调速器；用户态由 `fengchi-boot` 模块负责「开机准备好 + 玩游戏时切过去」。**

> 关键架构事实：`scx` 调速器**不是内核自带的**，它由厂商模块 `oplus_bsp_sched_ext.ko` 提供，
> 而设备上唯一 insmod 它的是风驰守护模块的 `service.sh` ⇒ **停用守护模块 = 顺手把 `scx` 一起删掉。**

## 相关仓库与许可

- 风驰项目说明与模块下载：**gt5pro-hmbird**
- 内核源码：**gt5pro-kernel-src**
- GPL-2.0；本仓库只包含自己的代码与文档，第三方来源仅作致谢（见 `NOTICE.md`）
