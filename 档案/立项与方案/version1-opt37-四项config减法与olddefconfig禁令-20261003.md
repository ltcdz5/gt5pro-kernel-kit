# version1-opt37：四项 config 减法 + ⛔ 本树禁用 `olddefconfig`（2026-10-03）

> 现役 **version1-opt37**。承接 version1-opt36。

---

## 〇、现役

| 项 | 值 |
|---|---|
| 版本串 | `6.1.141-android14-11-o-ltcdz5-version1-opt37` |
| banner | `#62-ack304-version1-opt37 SMP PREEMPT` |
| 镜像 | `boot-version1-opt37-repacked.img` md5 **`36f4c73c84491dd6beaa9717cd4b3143`** |
| 裸内核 | `perf37/Image.p37` md5 `676b6cc93ce6813144c6c32ca980f617`（**38,095,360 B**；P36 = 38,357,504 ⇒ 小 256 KB） |
| 源码 | commit `48e095183`，tag `version1-opt37` |
| 规模 | **2 文件**（`arch/arm64/configs/gki_defconfig` + `scripts/setlocalversion`）**零代码改动** |
| 刷后 | `lsmod` **621**、`wlan0` UP、oops 0、pstore 0、SSG `[ssg]`、`/data` f2fs、蓝牙 ON、ping 17ms、UBSAN 痕迹 **0** |
| 回退首选 | **opt36** `boot-version1-opt36-repacked.img` md5 `6610944ca925083835e2b5763c92f3f6` |

---

## 一、改了什么（纯 config，四项）

| 项 | 从 | 到 | 性质 |
|---|---|---|---|
| `CONFIG_UBSAN`（连带 `TRAP`/`BOUNDS`/`LOCAL_BOUNDS`/`SANITIZE_ALL`） | `y` | `n` | 去掉**调试探针**（不是漏洞缓解） |
| `CONFIG_INIT_ON_ALLOC_DEFAULT_ON` | `y` | `n` | 去掉**分配清零加固** |
| `CONFIG_INIT_STACK_ALL_ZERO` → `CONFIG_INIT_STACK_NONE` | `y` | `n`→`y` | 去掉**栈清零加固** |
| `CONFIG_ZRAM_MEMORY_TRACKING` | `y` | `n` | **回到真原厂**（原厂本来就是 n） |
| `CONFIG_RCU_NOCB_CPU_DEFAULT_ALL` | `y` | `n` | **回到真原厂**（原厂 n；省 8×3 个 `rcuo/N` kthread） |

### 依据（子代理独立重查 + 我方复核）
- **UBSAN 确实在跑**：`out/mm/.page_alloc.o.cmd`、`kernel/sched/.core.o.cmd`、
  `fs/f2fs/.compress.o.cmd`、`block/.blk-mq.o.cmd` 全含
  `-fsanitize=array-bounds -fsanitize=local-bounds -fsanitize-undefined-trap-on-error`
  ⚠️ **别用"System.map 里 `__ubsan_handle_*` = 0"当它没开的证据** —— TRAP 模式本来就不产生 handler
- **`INIT_STACK_ALL_ZERO` 每个 `.o` 都有 `-ftrivial-auto-var-init=zero`** —— **既有文档从未提过这项**
- `ZRAM_MEMORY_TRACKING` / `RCU_NOCB_CPU_DEFAULT_ALL` 在**真原厂**（`refs/stock_config.gz`）是 `n`
  ⇒ 是**我们多开的**，关掉 = 回到原厂
- 效应量诚实估计：**合计 2~8%**（内核码密集路径），**对开机墙钟 0**；本机尺子测不出（≤2%）
- ⚠️ 其中 UBSAN / INIT_ON_ALLOC / INIT_STACK 三项是**"用缓解网换性能"**，回退各只需改一行 config

---

## 二、⛔⛔ 本次踩的大坑：**本树绝对禁止 `olddefconfig`**

### 事故
我校验配置时跑了 `make olddefconfig O=out`（**不带工具链变量**）⇒ kconfig 的
**工具链探测全部失败** ⇒ 静默丢掉了**一大批**选项，其中致命的：

```
CONFIG_COMPAT=n              ← ★★★ task_struct/mm_struct 等核心结构体尺寸全变 ⇒ ABI 全塌
CONFIG_LTO_NONE=y            ← ThinLTO 丢
CONFIG_CFI_CLANG=n           ← 控制流完整性丢
CONFIG_SHADOW_CALL_STACK=n   ← 影子调用栈丢
CONFIG_KASAN_GENERIC=y       ← KASAN 模式从 HW_TAGS 掉回 GENERIC（choice 默认值）
CONFIG_ARM64_SW_TTBR0_PAN=n
```

**连锁反应**：`HAS_LTO_CLANG` 依赖 `!KASAN || KASAN_HW_TAGS`
⇒ KASAN 一变成 GENERIC，**LTO 也不成立** ⇒ 依赖 LTO 的 CFI 再跟着塌。

### 双闸门当场拦下（**第 5 次真救场**）
```
闸门1  消失=197 个导出、命中厂商 30 个   → FAIL 判砖
闸门2  会拒绝装载的模块 = 493（全部！）
```
⇒ **这是"刷了必砖"的那一类**（493 模块全废 = 完全没有 WiFi/蓝牙/驱动）。

### 正确做法（已固化）
1. ⛔ **绝不在本树跑 `olddefconfig`** —— 它做**依赖重解析**，而工具链探测在本环境不成立
   （**即使加了 `LLVM=1` 也不行**，实测仍丢）
2. ✅ 走项目原本的可复现路径：**`make gki_defconfig O=out`** —— **字面写入，不重解析**
   （`gki_defconfig` 就是真值源；P5 那次"把 config 增量录进 `gki_defconfig` 使构建可复现"的设计意图就在这）
3. ✅ `make Image` 触发的 **`syncconfig` 不会重解析**，安全
4. ✅ 任何 config 改动**同时写 `out/.config` + `arch/arm64/configs/gki_defconfig`**
5. ✅ 改完 config **必须过双闸门**，闸门2 必须仍是 `= 1`

---

## 三、验证

```
make rc=0 错误=0
闸门1  新增=50 消失=1 | 命中厂商 新增=0 消失=0   PASS   ← 与 P36 完全一致
闸门2  会拒绝装载的模块 = 1（bluetooth.ko / sk_filter_trim_cap）← 与 P36 完全一致
版本串 / 横幅 / Image 大小 38,095,360 B / UBSAN 痕迹 0 / CFI 痕迹 3
auto.conf 复核：LTO_THIN=y、CFI=y、SCS=y、KASAN_HW_TAGS=y 都在（syncconfig 没再丢）
```

---

## 四、一条待复核
设备上 `/sys/block/zram0/` 里**仍有 `idle` 文件**，而 `ZRAM_MEMORY_TRACKING=n` 理论上应让它消失。
⇒ 要么该选项未真正生效，要么 `idle` 由别处提供。**下次顺手查**（`ls /sys/block/zram0/`）。
