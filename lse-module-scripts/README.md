# LSE 调度扩展（lse_sched）

给 **真我 GT5 Pro（SM8650 / 6.1.141 OKI 自编内核）** 自编内核用的
**LSE（LunarKernel Scheduling Extention）** 管理模块。

## ⚠️⚠️ 风险告知（务必先读）

| 风险 | 说明 | 应对 |
|---|---|---|
| **开机卡死循环** | 在**开机早期**加载该模块 ⇒ 卡锁屏 + 看门狗重启循环（本项目实测过一次，需 ADB 救援） | 本模块**强制延时 120 秒**；**绝不要**放进 `post-fs-data` 或任何早期脚本 |
| **无法卸载** | 加载后标记 `[permanent]`，`rmmod` **必然失败**（源码无 `module_exit`） | **只能重启卸载**；回退第一步永远是**先切回 `uag`**（`action.sh`），不是 rmmod |
| **写 0 崩内核** | 往 `sched_ravg_window_frame_per_sec` 写 `0`/负数 ⇒ 除零 ⇒ 内核崩 | **永远不要写 0**；要调就写 60/90/120/240 |
| **可能 panic** | 内部一致性检查失败 ⇒ 直接 panic（`LSE_DEBUG_PANIC` 是编译期常量） | 重启即恢复；开机默认 `uag`，**不会 bootloop** |
| **轻载可能变钝** | 最低频率被拉低到 ~0.5GHz（原厂 1.25GHz），滑动/点按可能变慢 | 观察体感；不满意就 `action.sh` 切回 `uag` |
| **厂商槽位冲突** | 与 `oplus_bsp_sched_assist` 共用 `task_struct.android_vendor_data1[63]` | 出现异常先停用本模块 |
| **内核绑定** | `.ko` 依赖本机 vendor hook 与结构偏移，是给 `-opt10` 编译的 | 换内核后**先重新验证 CRC** 再用 |

## 它做什么
开机后 **延迟加载** `lunar_bsp_ext_sched.ko`（"最小化风驰"：Slim-WALT 负载跟踪 + `lunar_ext_gov` 调速器），
切到 `lunar_ext_gov`，并**重启 Scene 让它重读配置**（否则 Scene 会把调速器改回 `uag`）。

## 来源与许可（重要）

| 内容 | 来源 | 许可 |
|---|---|---|
| **`lunar_bsp_ext_sched.ko`** | **LunarKernel 项目 / 作者 Cloud_Yun**<br>`github.com/LunarKernel-Dev/lunarkernel_sched_extention` | **GPL v2** |
| 部署配方（原子部署 + `chmod 555` + 杀 Scene daemon 使其重读） | **「Turbo 调度」模块 / 作者 Turbo** | 思路借鉴 |
| 本模块脚本外壳（`service.sh`/`action.sh`/`uninstall.sh`/`delay.conf`） | 本项目 | 随项目许可 |

- ⚠️ **本项目没有 LSE 源码**，也**无法证实**这个二进制与上游源码一致（它是为本机内核树专门编译的，
  vermagic = `6.1.141-android14-11-o-ltcdz5-opt10`）
- ⚠️ 上游 LSE 据社区情报**源自 OPPO `hmbird_gki` 的拆改**；若涉闭源代码，**再分发风险由发布者承担**
- 再分发 GPL v2 二进制时，**必须**标注作者与许可，并提供源码获取方式（本项目只能给出上游链接）

## 文件
| 文件 | 作用 |
|---|---|
| `service.sh` | 开机：等 `boot_completed` → **延时 120s** → `insmod` → 切 governor → **重启 Scene**。**立即返回，不阻塞开机** |
| `action.sh` | 管理器「操作」按钮：LSE ↔ uag 切换；并顺手解除 `profile.json` 只读 |
| `uninstall.sh` | 卸载：切回 `uag` + **还原 Scene 配置**（内容/权限/属主）+ 重启 Scene |
| `delay.conf` | `DELAY_AFTER_BOOT=120` / `SWITCH_GOVERNOR=1` / `RESTART_SCENE=1` |
| `post-fs-data.sh` | **故意留空**（早期加载会卡死循环） |
| `scene_profile.orig.json` | Scene 原始 `profile.json` 备份（9496 字节），供卸载还原 |
| `lunar_bsp_ext_sched.ko` | LSE 模块本体（1.5MB，GPL v2，Cloud_Yun） |

## 日志
`/data/local/tmp/lse_module.log`

## 与 Scene 的配合
本模块会把 Scene 的 `profile.json` 里 `@governor` 的 `lunar_ext_gov` 排第一，并设为 **555 只读**，
防止 Scene 把配置改回去（配置里排第一的会被优先尝试）。
**要恢复可写**（以便在 Scene 里改调度设置）：点管理器「操作」，`action.sh` 会自动解锁。

## 实测到的效果（本机）
- 最低频率：p0 `1248000→556800`、p5 `1286400→499200` 等 ⇒ 空载可掉到 **0.5GHz**
- 满载升频：p2 可达 **3.07GHz** ⇒ **未压满载性能**
- 切应用不回退；oops 0
- ⚠️ **省电幅度与轻载手感尚未可信实测**（测量时手机在充电且有背景噪声，三次测量均失败）

## 卸载与还原
管理器里卸载本模块即可 —— `uninstall.sh` 会切回 `uag`、**还原 Scene 原始配置**、重启 Scene；
LSE 内核模块随下次重启消失。

> 完整分析（合规细节、缺陷清单、性能功耗推断、测量失败记录）见
> `gt5pro-kernel-kit` 的《档案/闸门与ABI/LSE调度扩展-来源合规缺陷与风险告知-20261004.md》
