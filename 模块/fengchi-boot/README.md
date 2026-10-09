# fengchi-boot 模块说明

配套「自编内核」使用的风驰自启模块。**只对特定自编内核有效**，单独刷没有任何作用。

## 它做什么（开机自动跑，不用管）

1. **准备官方调度环境**：把 `gameswitch` / `oiface` / `horae` 等开关打开，并把 `oiface`、`horae`、`gameopt_hal_service`、`vendor.urcc-hal-aidl` 这几个服务拉起来（风驰依赖它们）；
2. **按依赖顺序加载厂商模块栈**：`oplus_bsp_game_opt` → `oplus_bsp_sched_assist` → `oplus_bsp_sched_ext`，**风驰要用的 `scx` 调速器就是最后那个注册的**；
3. **恢复 MGLRU**：把 `/sys/kernel/mm/lru_gen/enabled=Y`、`min_ttl_ms=1000` 写回去；
4. **启动守护**：进入后台循环，检测到游戏就切 `scx`，退出游戏就切回官方默认。

## 文件清单（每个文件干什么）

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块信息（给 KernelSU / Magisk 管理器看的名字、版本、作者）|
| `service.sh` | **开机主脚本**：做上面 1~4 步；由管理器在开机后自动执行 |
| `fengchi-gov.sh` | **守护脚本**：常驻后台，轮询「有没有游戏在玩」，负责切/切回调速器 |
| `fengchi.conf` | **配置文件**：想改行为改这里（见下）|
| `README.md` | 本说明 |

## 日志在哪

日志直接写在 **Download 目录**，用文件管理器就能看：

| 文件 | 内容 |
|---|---|
| `/sdcard/Download/fengchi-boot.log` | 开机过程：环境准备、模块加载、MGLRU、守护是否起来 |
| `/sdcard/Download/fengchi-gov.log` | 守护运行记录：什么时候切到 scx、什么时候切回去 |

日志超过 `LOG_MAX` 行会自动截断（默认 2000 行），不会无限变大。

## 配置项（`fengchi.conf`）

| 配置 | 默认 | 说明 |
|---|---|---|
| `IDLE_GOV` | `uag` | **没有游戏时**切回的调速器。`uag` 是 OPPO 官方默认（推荐）；也可以填 `walt`；**留空表示不切回** |
| `SCX_GOV` | `scx` | **检测到游戏时**切换到的调速器。正常不要改 |
| `POLL_SEC` | `4` | 轮询间隔（秒）。越小越灵敏，耗电略增 |
| `LOG_DIR` | `/sdcard/Download` | 日志目录。想换个位置就改这里 |
| `LOG_MAX` | `2000` | 日志最大行数，超过则保留最后 500 行 |

改完配置后：**重启生效**；或者手动执行一次 `sh /data/adb/modules/fengchi-boot/service.sh`。

## 怎么确认生效

进游戏后看 CPU 调速器（Scene 里能直接看，或执行）：

~~~
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
~~~

显示 `scx` = 生效 ✓；退出游戏后回到 `uag` = 正常 ✓

## 前置条件（不满足就没用）

- 配套的自编内核（OPPO 系 OKI 基线，6.1.141 那种）；
- 设备树 hmbird 类型为 `HMBIRD_OGKI`；
- 厂商模块在位（`oplus_bsp_sched_ext.ko` 及其依赖）。

## 注意

- **不要**用任何工具去「固定」风驰调度（实测会导致硬挂机）；
- 建议**卸载「官方调度屏蔽」类模块**（例如 IMS_VAROS），否则官调属性被清空、风驰不工作；
- 可能与 Scene 的调度设置冲突（未做完整测试），建议先关掉 Scene 的调度/调速器设置。

## 卸载

在 KernelSU / Magisk 管理器里直接移除本模块，重启即可；残留日志在 Download 目录，可自行删除。