# 第12步 · 反解出厂内核里 ext_module_loaded 的消费者，并把缺失的触发补进我们的树

> 日期：2026-10-09 ｜ 设备：真我 GT5 Pro（RMX3888 / SM8650 / ColorOS 16）｜ 内核：6.1.141 自编（wt-core 分支 `hmbird-core-stageG`，从 `hmbird-core-stageD` `714fadacba9f` 分出）
> 本轮性质：**静态反解出厂二进制 + 落地补丁 + 构建 + 闸门**。未刷机、未动设备、未动主线树（只动 `wt-core`）。
> 唯一基准：出厂 `Image.stock`（35,695,104 B，SHA256 `78763c46048c75a324fcbcab90df989dbf53ac235fedd67f6b85088638a52c65`）
> 自校验对照件：本树 `Image.opt55`（SHA256 `4cccf0d6a08c35dc4025fd55bd16b21bcea8855349fc6cae9982883c56dcf47e`，与 `_audit/System.map-opt55` 逐名互校）
> 归档：`F:\工作区\_lab\2026-10-09\scx-step12\${B}（`evidence/` 全部反汇编与扫描原始输出、`*.py` 可重放）

---

## 0. 一句话结论

**出厂内核里 `ext_module_loaded` 的消费者只有一个：`ext_ctrl()`（`Image.stock` `0xffffffc0082ece24`）。**
全镜像 ADRP 扫描证明它是**唯一**读该对象的代码；同时全镜像**没有任何代码写它**（写者只能是厂商模块 `oplus_bsp_sched_ext.ko`）。
我们树里同一血统的那支代码叫 `hmbird_ctrl()`，但把闸门接在**启动时就被 `hmbird_misc_init()` 拉高**的 `hmbird_module_loaded` 上，于是
①出厂「模块没装载就不许开」的闸门在我们这儿**常开**，②`ext_module_loaded` 成了没人读的死变量。
Stage G 把闸门换回 `ext_module_loaded`（并在 `/proc` 触发点改用 factory 名字 `ext_ctrl`），语义与出厂逐条对齐，导出集不变。

---

## 1. 方法（三步，每步都做了阳性自校验）

### 1.1 kallsyms 带地址解出（本轮新增能力；第 11 步只解出名字，地址列卡住）

纯 Python 自研解码器 `kallsyms_extract.py`（WSL 内无 numpy/网络），直接对 raw arm64 Image 解：

| 结构 | 出厂 `Image.stock` | 本树 `Image.opt55` |
|---|---|---|
| `relative_base` | `0xffffffc008000000` | `0xffffffc008000000` |
| `kallsyms_offsets` | foff `0x12b6c20`（vaddr `0xffffffc0092b6c20`） | foff `0x11c0ac8` = **`System.map-opt55` 同名符号地址，完全一致** |
| `kallsyms_num_syms` | **102,901** | 116,258 |
| `kallsyms_names` | foff `0x131b408`，长 1,410,565 B | foff `0x1232360`，长 1,715,460 B |
| `markers` / `seqs_of_names` | `0x1473a10` / `0x1474058` | `0x13d5068` / `0x13d5784` |
| `token_table` / `token_index` | `0x14bf638` / `0x14bf9c0` | `0x142a9f0` / `0x142ad90` |
| 最高符号地址 | `0xffffffc00a3b0000`（= 头部 `image_size` 字段 `0x23b0000` ✓） | `0xffffffc00a730000` |

**第 11 步没解出地址列的真正原因（本轮定位）**：`kallsyms_offsets` 与 `kallsyms_relative_base` 两个标签之间有一段 **8 字节对齐填充**。
`output_label()` 对每个标签都发 `.balign 8`（见 `scripts/kallsyms.c:369`），而 `4*num_syms` 未必是 8 的倍数：
出厂 `4*102901 = 411604 ≡ 4 (mod 8)` ⇒ **offsets 数组起点比「relative_base − 4N」再往前 4 字节**。
opt55 的 `4*116258 = 465032 ≡ 0 (mod 8)`，恰好没有填充，所以用 opt55 当对照时看不出来。
（第一版按 `−4N` 解出来的表整体**错位一条符号**，正是这个坑；已修，见 §1.4 的硬校验。）

**硬校验（两条独立通道）**

1. `__ksymtab_<name>` 的 `value_offset` 必须指向同名 kallsyms 地址：
   * `__ksymtab_ext_module_loaded` 在 `0xffffffc0096103a8`，读出 `value = 0xffffffc00a217850`、`name = "ext_module_loaded"` ⇒ 与 map 里 `Bext_module_loaded @0xffffffc00a217850` **MATCH**。
2. 反汇编自校验：map 说 `scx_get_md_info @0x2ee210`，反汇编正好是
   `adrp x8,0xffffffc00a217000; mov w9,#0x1000; ldr x8,[x8,#3584]; str x8,[x0]; str x9,[x1]; ret`
   —— 与 `kernel/sched/hmbird_export.c` 里早先记下的出厂实况**逐字一致**（第 4 步的记录，独立来源）。

⇒ 出厂 `stock.map`（102,901 条、带地址）可用；产物：`_lab/2026-10-09/scx-step12/stock.map`。

### 1.2 全镜像 ADRP 扫描（找「谁读 / 谁写」）

`adrp_scan.py`：逐 4 字节解码 `ADRP`（`(insn & 0x9F000000)==0x90000000`），按 `target = (pc & ~0xFFF) + (sext(imm21)<<12)` 命中目标 4K 页，
再向后跟踪最多 8 条指令的 `mov/add` 链，算出 `ldr/ldrsw/str/ldrb/...` 的**最终字节偏移**。
因为 `ext_module_loaded(0x…850)`、`hmbird_dir(0x…858)`、`__scx_ops_enabled(0x…860)`、`iso_masks(0x…868)`
挤在同一页 `0xffffffc00a217000` 上，所以必须靠偏移区分——这也是它能给出「唯一读者」结论的原因。

### 1.3 全镜像 BL 扫描（找「谁触发」）

`callers.py`：逐 4 字节解码 `BL`（`(insn & 0xFC000000)==0x94000000`），`target = pc + (sext(imm26)<<2)`，
再用 `stock.map` 反查调用点所属函数。

### 1.4 关键坑（留档，避免后来者重踩）

1. `kallsyms_offsets` → `kallsyms_relative_base` 之间的 **8B 对齐填充**（§1.1）。
2. kallsyms 里的符号名**首字符是类型字符**（`T_text`、`Bext_module_loaded`），按名字 grep 时不能带 `^` 锚 `name$`。
3. 出厂 Image 的 file offset **就是** vaddr − `0xffffffc008000000`（含 `0x10000` 处的 EFI stub 区；`_text == 0xffffffc008000000`）。

---

## 2. 出厂消费者定位证据

### 2.1 相关对象地址（出厂 `Image.stock`）

| 符号 | 地址 | 段 | 备注 |
|---|---|---|---|
| `ext_module_loaded` | `0xffffffc00a217850` | B | 导出（`__ksymtab @0x96103a8`） |
| `hmbird_dir` | `0xffffffc00a217858` | B | 导出 |
| `__scx_ops_enabled` | `0xffffffc00a217860` | B | 导出 = OPPO 版 `scx_enabled()` 的实体 |
| `iso_masks` | `0xffffffc00a217868` | B | 导出 |
| `scx_enable` | `0xffffffc00a217fe0` | B | `/proc/hmbird_sched/scx_enable` 背后的 int |
| `sw_type` | `0xffffffc00a217eb0` | B | 切换来源标记 |
| `ext_ctrl` | `0xffffffc0082ece24` | T | **消费者**（未导出） |
| `slim_common_write` | `0xffffffc0082f14c8` | t | 触发者 1（/proc 写） |
| `scx_err_exit_workfn` | `0xffffffc0082ee620` | t | 触发者 2（错误退出） |
| `scx_ops_disable_workfn` | `0xffffffc0082f4634` | t | 关路径 |
| `task_is_scx` | `0xffffffc0082ecb18` | T | 导出（`p->sched_class == &ext_sched_class`） |

### 2.2 唯一读者：`ext_ctrl` 的入口守卫（逐条指令）

    ffffffc0082ece4c: f000f949  adrp x9, 0xffffffc00a217000
    ffffffc0082ece58: b9485128  ldr  w8, [x9, #2128]     ; 2128 = 0x850 = ext_module_loaded
    ffffffc0082ece5c: 340009a8  cbz  w8, 0xffffffc0082ecf90
    ffffffc0082ece68: 36000ae0  tbz  w0, #0, 0xffffffc0082ecfc4   ; 之后才看 enable 参数

「未装载」分支（`0x2ecf90`）把字符串 **`"ext module unloaded\n"`（`0xffffffc009508239`）** 交给 switch-log 助手，
然后 `mov w19, #0xffffffea`（**−EINVAL**），走 `0x2edfc0` 的公共收尾 `mov w0, w19; …; ret`
⇒ **`int ext_ctrl(bool enable)`，未装载时对 enable/disable 一律返回 −EINVAL**。

### 2.3 没有任何代码写它：整页访问偏移直方图

`0xffffffc00a217000` 这一页上每个被访问到的偏移及其**访问点数**（`hist.py`，全镜像）：

    0x0850 : 1     <- ext_module_loaded  ← 全镜像只有 1 个访问点（且是 §2.2 的 ldr）
    0x0858 : 1     <- hmbird_dir
    0x0860 : 18    <- __scx_ops_enabled
    0x0868 : 10    <- iso_masks
    ...
    0x0fe0 : 6     <- scx_enable
    0x0fec : 29    <- watchdog_enable / save_gov 一带

⇒ `ext_module_loaded` 在全镜像里**只被读一次、从不被写**。写它的人只能是厂商模块
（`_lab/2026-10-08/scx-step4c/oplus_bsp_sched_ext.ko.json` 的 UND 列表里就有 `ext_module_loaded`）。
**这条「无写者」是决定性的**：它说明出厂内核自己**从不**拉高这个闸门，闸门完全交给模块。

### 2.4 触发者：`ext_ctrl` 的两个调用点（全镜像 BL 扫描）

    call @0xffffffc0082f16d4 -> ext_ctrl(0x2ece24)   来自 slim_common_write
    call @0xffffffc0082ee644 -> ext_ctrl(0x2ece24)   来自 scx_err_exit_workfn  （mov w0,wzr ⇒ ext_ctrl(false)）

`slim_common_write` 的调用序列（`/proc/hmbird_sched` 写路径，逐条）：

    ffffffc0082f16bc: d000f928  adrp x8, 0xffffffc00a217000
    ffffffc0082f16c4: b90eb11f  str  wzr, [x8, #3760]   ; 3760 = 0xEB0 = sw_type = 0
    ffffffc0082f16c8: b94fe128  ldr  w8, [x9, #4064]    ; 4064 = 0xFE0 = scx_enable
    ffffffc0082f16d0: 1a9f07e0  cset w0, ne             ; w0 = !!scx_enable
    ffffffc0082f16d4: 97ffedd4  bl   0xffffffc0082ece24 ; ext_ctrl(!!scx_enable)
    ffffffc0082f16d8: 928001a8  mov  x8, #-14           ; -EFAULT
    ffffffc0082f16e0: 9a880273  csel x19, x19, x8, eq  ; rc != 0  ->  写返回 -EFAULT

### 2.5 启用侧：`__scx_ops_enabled` 的读 / 写点（出厂）

* 读（`ldr`）：`scheduler_tick`、`pick_next_task_idle`、`set_next_task_idle`、`put_prev_task_idle`、`scx_notify_sched_tick`、
  `scx_fork`、`scx_post_fork`、`scx_cancel_fork`、`scx_check_setscheduler`、`task_on_scx`、`ext_ctrl`、`scx_debug_show`、
  `hmbird_panic_handler`（ldrsw）、`__schedule` —— 即 OPPO 版 `scx_enabled()` 的全部落点。
* 写（`str`）**只有两处**：
  * `str w8, [x25, #2144]` @`0x2ed49c`，紧跟 `mov w8, #1`（`0x2ed484`）—— **在 `ext_ctrl` 体内**（`scx_ops_enable()` 被完全内联进来），即 `atomic_set(&__scx_ops_enabled, true)`。
  * `str wzr, [x25, #2144]` @`0x2f47e0` —— 在 `scx_ops_disable_workfn` 体内，即 `atomic_set(&__scx_ops_enabled, false)`。

⇒ **启用侧的唯一入口就是 `ext_ctrl(true)`**；`__scx_ops_enabled` 自己不会凭空变 1。

### 2.6 出厂那一步的确切语义（还原为源码）

    /* MUST load ext module before enable ext scheduler
     * load track & ext gover implemented in ext module */
    int ext_ctrl(bool enable)
    {
            if (!atomic_read(&ext_module_loaded)) {          /* 唯一读者 */
                    switch_log(hmbird_enabled()?ENABLED:DISABLED, 0, enable,
                               "ext module unloaded\n");
                    return -EINVAL;                          /* 未装载：enable/disable 都拒绝 */
            }
            if (enable && state in {ENABLED, ENABLING, PREPPING})  return -EBUSY;   /* "already enabled(ing)\n" */
            if (!enable && state in {DISABLING, DISABLED})         return -EBUSY;   /* "already disabled(ing)\n" */
            if (enable) return bpf_scx_reg(NULL);            /* -> scx_ops_enable(NULL) -> atomic_set(&__scx_ops_enabled,1) */
            else        return bpf_scx_unreg(NULL);          /* -> scx_ops_disable(SCX_EXIT_UNREG); flush */
    }

**与 `register_hmbird_sched_ops` / `slim_walt` 的关系**：出厂的启用侧与它们**无关**。
唯一入口是 `/proc/hmbird_sched/scx_enable`（写 `scx_enable` int）→ `slim_common_write` → `ext_ctrl`；
`register_hmbird_sched_ops`/`hmbird_sched_class`/`hmbird_module_loaded` 这些名字在出厂 `Image.stock` 的符号表里
**一个都没有**（与 Stage E 的字符串普查结论一致）；出厂用的是 `ext_sched_class` + `scx_*` 命名 + `ext_module_loaded`。
`slim_walt` 属于 `slim_sched` 那一支（`/proc/slim_sched/*`），不参与 scx 启用判定。

---

## 3. 我们树的差异（逐条，已 grep 证实）

| # | 出厂 | 我们树（Stage D 结束时） | 性质 |
|---|---|---|---|
| 1 | `ext_ctrl()` 读 `ext_module_loaded` | **全树没有任何代码读 `ext_module_loaded`**（只有 `kernel/sched/hmbird_export.c:71-72` 的定义与导出） | **消费者缺失** |
| 2 | 闸门 = `ext_module_loaded`（只有厂商模块会写） | 闸门 = `hmbird_module_loaded`，且 `hmbird/hmbird_misc.c:145 set_hmbird_module_loaded(1)` 在**启动时**就拉高 | **闸门对象错位 + 常开** |
| 3 | 触发点 `slim_common_write` → `ext_ctrl` | `kernel/sched/hmbird_sched_proc_main.c` 的 `scx_enable_proc_write` → `hmbird_ctrl` | **触发点接在错名字上**（阶段 D 的接线，本体没错） |

**同名同体的证据链（本轮最关键的判断）**：我们树 stage A 导入的 `kernel/sched/hmbird/` 家族，与出厂是**同一份源码、两套命名**：

| 出厂（SM8650，`Image.stock`） | 我们树导入件（SM8750 命名） | 校验 |
|---|---|---|
| `ext_ctrl` @`0x2ece24` | `hmbird_ctrl()` @`hmbird.c:3991` | 守卫逻辑、−EINVAL、字符串 `"ext module unloaded\n"`、状态机三分支、`bpf_*_reg/unreg` 全同 |
| `scx_err_exit_workfn` @`0x2ee620` | `hmbird_err_exit_workfn()` @`hmbird.c:3709` | 两者都 `ctrl(false)` 开头 |
| `task_on_scx` @`0x2ecb64`（`return *(u32*)0x…860 != 0`） | `task_on_hmbird()` @`hmbird.c:3460`（`return hmbird_enabled();`） | 反汇编逐字对应 |
| `scx_get_md_info` @`0x2ee210` | `hmbird_get_md_info()` @`hmbird.c:4199` | 反汇编与源码同 |
| `__scx_ops_enabled` | `__hmbird_ops_enabled` | 语义同 |
| `ext_module_loaded`（导出，模块写） | `hmbird_module_loaded`（内核启动写） | **← 就是这条错位** |

⇒ 结论：出厂与我们的差别**不是算法**，而是**闸门变量**。把闸门换回 `ext_module_loaded` 就是「补上缺失的消费者」。

---

## 4. 落地修改（分支 `hmbird-core-stageG`）

### 4.1 改了什么（5 文件，+71/−29）

1. `kernel/sched/hmbird/hmbird.c`
   * `hmbird_ctrl()` 的闸门 `hmbird_module_loaded` → **`ext_module_loaded`**（函数体其余一字未改）；
   * 该函数改名为 factory 名字 **`ext_ctrl()`**，`hmbird_ctrl()` 保留为**一行别名** `return ext_ctrl(enable);`
     ⇒ 家族内另两个调用点（`hmbird_err_exit_workfn()`、`hmbird_sched_proc.c`）自动继承同一个闸门；
   * 函数头写下完整的出厂证据（地址、指令、调用点、无写者）。
2. `kernel/sched/hmbird_sched_proc_main.c`：`scx_enable_proc_write()` 的 `hmbird_ctrl(!!val)` → **`ext_ctrl(!!val)`**（出厂触发点），
   并把拒绝时的 `pr_warn`／注释改成 `ext_module_loaded` 口径。
3. `kernel/sched/hmbird/hmbird_sched.h`、`kernel/sched/hmbird.h`：声明 `extern int ext_ctrl(bool enable);`。
4. `kernel/sched/hmbird/slim.h`：`extern atomic_t ext_module_loaded;`（定义仍在 `hmbird_export.c`，未动）。

### 4.2 纪律核对

* **没有新增任何 `EXPORT_SYMBOL`**：只加了一个 `extern` 声明与一个非 static 函数 `ext_ctrl`（出厂同样不导出它，见 §2.1）⇒ 导出集不变。
* **`hmbird_export.c` 一行未动**（10 个导出原样）。
* **没有 olddefconfig**；`Kconfig` 未动。
* 唯一语义变化：`/proc/hmbird_sched/scx_enable=1` 在模块未装载时由「默默成功」变为**明确 −EFAULT**（= 出厂行为）。

### 4.3 构建与闸门

### 4.3 构建与闸门（全过）

**构建**：`/home/builder/kwork/wt-core` @ `af6c816473e1`，`O=/home/builder/kwork/out-core`，
`make -j16 LLVM=1 ARCH=arm64 CC="ccache clang" LD=ld.lld HOSTCC=clang O=… KBUILD_BUILD_VERSION=stageG-1 Image` ⇒ **make rc=0**（日志 `_lab/2026-10-09/scx-step12/build.log`）。
Image：39,406,080 B；定点 CRC 覆写前 md5 `57dd72d6a0fb4472406bf1bc86f12a2f` → 覆写后 md5 `f2781003f4e17ecfaeb61203adf833bc`。
（说明：`sk_filter_trim_cap`／`iso_masks`／`task_is_scx` 三项 CRC 与出厂模块期望值不一致是**既有已知项**，靠 `patch_crc_targeted.py` 定点覆写 Image + symvers 解决；
Stage D 的闸门同样是 `already_patched=True` 才判 PASS，本轮流程与之一致。未覆写前的第一次闸门输出留在 `gate-stageG-preCRC.log` 作对照。）

`python3 /mnt/f/工作区/_audit/gate_core.py --tree /home/builder/kwork/wt-core --o /home/builder/kwork/out-core --label stageG`：

| 闸门 | 结果 |
|---|---|
| 1) patch_crc_targeted | ⚠️ WARN_ALREADY_PATCHED（提示，与 Stage D 同） |
| 2) audit_all（493 模块） | ✅ **PASS** modules=493 **missing=0 crc=0** |
| 3) gate_vko_crc | ✅ **PASS** **拒载=0**（导出=15489） |
| 4) gate_new_exports | ✅ PASS 新增=15 消失=0 命中新增=6 **遮蔽=0** |
| 5) 导出集逐名 diff | ✅ **PASS** 候选=15489 基线=15489 **逐名一致=True**，added 差异=0 gone 差异=0 |
| 6) proc 条目集对账 | ✅ PASS 保留 21/21，DROP 异常=0 |
| **判定** | **PASS** |

**手工补充对账**

* `cut -f2 out-core/vmlinux.symvers | sort -u | wc -l` = **15489**；与基线 `scx-step5d/exports-opt60-final.names` 逐名 `diff` **输出为空（rc=0）**。
* `out-core/System.map`：`ffffffc008147c48 T ext_ctrl`、`ffffffc008148f04 T hmbird_ctrl`（都是 `T` = 非导出）；
  `vmlinux.symvers` 里**既无 `ext_ctrl` 也无 `hmbird_ctrl`** ⇒ 导出集未变 ✓
* `ext_module_loaded` 的导出 CRC 仍为 `0x2d91f265`（一字未动）✓
* Commit：`af6c816473e1f07a771caf21edc21263a22e8e8c`（分支 `hmbird-core-stageG`，5 文件 +70/−29）

**闸门全过后的判读**：Stage G 只是把闸门接对，**没有改变导出集、没有改变任何既有模块接口**；
但它把「厂商模块写 `ext_module_loaded=1` 之后内核才有可能点亮 ext 调度」这条出厂因果链**接通**了 ——
在此之前，同一个写操作只会落进一个死变量，而 `/proc/hmbird_sched/scx_enable=1` 会因为我们的闸门常开而"看起来成功、实际不生效"。

---

---

## 5. 上机预期（供 Lead 验证）

在**装了厂商模块**的机器上（本树 `CONFIG_HMBIRD_SCHED_CORE=y`）：

1. **装载前**：`ext_module_loaded = 0`（zeroed .bss）。
   * `echo 1 > /proc/hmbird_sched/scx_enable` ⇒ `ext_ctrl(true)` 走未装载分支：
     `dmesg` 出现 `hmbird_sched: scx_enable=1 rejected: vendor module not marked loaded (ext_module_loaded==0); ...`（本树 printk）+ 家族自己的 switch-log `"ext module unloaded"`；
     写系统调用返回 **−EFAULT**；`cat /proc/hmbird_sched/scx_enable` 仍回显 `1`（int 是「用户意图」）；
     `cat /proc/hmbird_sched/hmbird_stats` 里 `enabled: 0`；
     `__scx_ops_enabled` 仍为 0 ⇒ `scx_enabled()` 假 ⇒ `__schedule`／`scheduler_tick`／`pick_next_task_idle` 都走老路，**不可能有调度器被点亮**。
2. **装载 `oplus_bsp_sched_ext.ko` 之后**：模块通过 `__ksymtab` 写 `ext_module_loaded = 1`（它是模块 UND 表里的符号）。
   * 再 `echo 1 > /proc/hmbird_sched/scx_enable` ⇒ 闸门打开 ⇒ `bpf_hmbird_reg(NULL)` → `hmbird_ops_enable()`：
     `__hmbird_ops_enabled` 变 **1**；`task_on_hmbird()` 由 0 变 1；`hmbird_sched_class` 进入 `for_each_active_class`；
     `/proc/hmbird_sched/scx_enable` 读回 1、`hmbird_enabled()` 也变 1（**这两个此前是「读回 1 而实际 0」，Stage G 之后才可能一致**）。
   * `echo 0` ⇒ `ext_ctrl(false)` → `hmbird_ops_disable()` → `__hmbird_ops_enabled` 回 0。
3. **判读要点**：`/proc/kallsyms | grep ext_module_loaded` 有地址（导出在）；用 kprobe 挂 `ext_ctrl` 应看到调用；
   若模块装载后写 1 仍 −EFAULT，说明模块 init 没有把 `ext_module_loaded` 写成 1（那就是厂商侧的另一处缺口，不是内核侧）。

---

## 6. 边界与未解决

1. **出厂 `ext_ctrl` 体内是 `scx_ops_enable(NULL)` 的全内联**，而我们树的 `hmbird_ops_enable(kdata)` 走的是导入家族自己的 enable 路径 ——
   二者语义对齐（同一份源码两套命名），但**没有逐字节比对过 enable 内部**；本轮只对齐「闸门 + 触发」这一层，符合任务边界（只补缺失的消费者/触发）。
2. 出厂 `ext_ctrl` 里 `scx_ops_enable` 被内联、`bpf_sched_ext_ops`／`bpf_scx_*` 在出厂符号表里**不存在**
   （BPF struct_ops 注册这条路出厂是拆掉的；这也解释了「注册 BPF 调度器会硬挂」）。
   我们树 `kernel/sched/ext.c` 仍是 OPPO OSS 版（含 `bpf_scx_reg`／`bpf_sched_ext_ops`）——**本轮未动它**，这是 Stage B 的既有形态。
3. 未刷机、未上机，以上预期均为静态推导；`ext_ctrl` 返回码、`__hmbird_ops_enabled` 翻转需 Lead 上机核对。
