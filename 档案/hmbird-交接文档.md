# hmbird sched_ext 移植 — 交接文档（2026-10-10 02:05）

## 一、目标
把 OPPO 的 **hmbird**（魔改 sched_ext 调度类，源自 SM8750）移植到
**Realme GT5 Pro / RMX3888 / SM8650 / ColorOS 16 / 自编译内核 6.1.141**，
让它能**启用并稳定接管任务调度**；对外发布镜像保持 `CONFIG_HMBIRD_SCHED_CORE=n`。

## 二、环境
| 项 | 值 |
|---|---|
| 内核树 | WSL `Ubuntu-24.04`，用户 `builder`，`/home/builder/kwork/wt-core`（分支 `hmbird-core-stageG`）|
| 构建输出 | `/home/builder/kwork/out-core` |
| 工作脚本 | `F:\工作区\_audit\`（构建/刷机/测试/取证脚本都在这里）|
| 设备工具 | `C:\Users\xutengfa\Downloads\platform-tools\{adb,fastboot}.exe`；设备序列号 `8ad67adf` |
| kit 仓库 | `C:\Users\xutengfa\Desktop\gt5pro-kernel\kernel-kit`（CHANGELOG 有全部阶段记录）|
| 内核源码仓库 | `C:\Users\xutengfa\Desktop\gt5pro-kernel\kernel-kit` / `gt5pro-hmbird` / `gt5pro-kernel-src` |
| WALT 源码 | `F:\工作区\walt-oppo-sm8650\`（25 文件，walt.c 5636 行）|

## 三、构建流程（务必照做）
```bash
cd /home/builder/kwork/wt-core
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH
O=/home/builder/kwork/out-core
# 配置：必须从零生成，只开 CORE（绝不要手改 DEBUG_INFO/BTF —— 会导致 CRC 漂移 ⇒ 模块拒载 ⇒ 启动循环）
rm -f $O/.config && make -j16 LLVM=1 ARCH=arm64 ... gki_defconfig
./scripts/config --file $O/.config --enable HMBIRD_SCHED_CORE
# 编译（只编 Image，约 90~150 秒增量）
make -j16 LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
  LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=$O KCFLAGS+=-O2 KCFLAGS+=-Wno-error \
  KCFLAGS+=-Wno-implicit-function-declaration KBUILD_BUILD_VERSION=75-ack304-v1.1-optNN Image
# CRC 定点覆写（必须 4/4，否则绝不可刷）
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/patch_crc_targeted.py \
  $O/arch/arm64/boot/Image $O/vmlinux.symvers
```
- 版本串在 `scripts/setlocalversion`（改一行即可）✓
- **硬闸门**：`grep -cE '^OK ' 日志` 必须 = 4；导出符号集必须 = **15489** ✓
- 打包：Windows 侧 `python F:\工作区\_audit\make_opt60.py F:\工作区\_audit\Image.optNN v1.1-optNN --boot-only` ✓

## 四、刷机流程（踩过的坑）
1. 必须进**完整 bootloader**：`fastboot getvar partition-size:boot_a` 应为 `0xC000000`（192MB）；
   若是 `0` ⇒ 受限模式 ⇒ 先 `fastboot reboot bootloader` 再刷 ✓
2. `fastboot flash boot_a <img>` → `fastboot set_active a` → `fastboot reboot` ✓
3. 脚本 `F:\工作区\_audit\run1NN.ps1` 已含上述检查 + 失败自动回退 opt60 ✓

## 五、取证三板斧（关键能力）
1. **内核日志面包屑**：测试脚本把进度写 `/dev/kmsg`（`echo "hmbird-t96: ..." > /dev/kmsg`）⇒ 硬挂后重启仍可读 ✓
2. **落盘现场**：设备 `/data/persist_log/backup/SYSTEM_LAST_KMSG.txt`（厂商 dmesg_dumper 写）✓
3. **WALT 断言**：`echo 1162141208 > /proc/sys/walt/panic_on_walt_bug`
   = 0x4544DE18（保留 print、关掉 panic）⇒ 能打出 `WALT-BUG selecting unaffined cpu=<cpu> comm=<名>(pid) affinity=0x<掩码>` ✓
   （写 0 会把所有 WALT 断言静音 ⇒ 丢证据；默认值 1162141211 = panic+print ✓）

## 六、当前状态（截至 02:05）
- **已修 34 个阶段**（commit 前缀 `Stage G` … `Stage AV`，全在 `hmbird-core-stageG` 分支）✓
- **里程碑**：调度器**能成功启用并保持**（`/proc/hmbird_sched/scx_enable=1` 稳定 30 秒以上 ✓，机器活着 ✓）
- **当前卡点**：厂商 WALT 的 `android_rvh_set_task_cpu` 断言
  `cpumask_test_cpu(new_cpu, p->cpus_ptr)` ⇒ 任务被放到**亲和性之外的 CPU** ⇒ `WALT-BUG` ⇒ panic ✓
  - 实测 opt102：`affinity=0x63`（CPU 0,1,5,6）的任务被放到 **cpu=2/3** ✗
  - **Stage AP** 已修 `select_cpu_from_cluster()` ✓；**Stage AV**（opt103，编译中）在唯一入口
    `select_task_rq_hmbird()` 统一校验 + 给 `task_can_run_on_rq()` 补亲和性检查 ✓
- 设备当前：**opt102**；回退件 **opt60**（md5 `5fd7909866e0de04b8e46cd9b388cc2e`）✓

## 七、剩余工作（按优先级，均有子代理报告支撑）
1. **测试 opt103**（Stage AV ✓ 编译中）⇒ 看 WALT 越权断言是否消失
2. **补 `reject_change_to_scx` 的 core.c 侧**（Stage AT/AT2 已做 ✓，待验证）
3. **BAL_KEEP 快路径**（参考实现 put_prev 有 2 个 watch 点，我们只有 1 个；`HMBIRD_TASK_BAL_KEEP` 零引用）
4. **tick 时钟三件套**（必须原子一起补，缺一件会永久挂死）：
   - `ext.h` 恢复 `scx_scheduler_tick()` 调用（现被注释）
   - `ext.c` 加 `tick_sched_clock` / `set_sched_clock_prepare` / `DECLARE_COMPLETION` / `complete()`
   - enable 里 `wait_for_completion_interruptible(&tick_sched_clock_completion)`
5. **两个 `iso_masks` 对象合并**（`nm vmlinux | grep iso_masks` 现在有 2 个；ext.c 用的是被 `cpumask_setall` 覆盖的那份）
6. 关闭路径（`scx_enable=0`）验证、游戏实测、功耗
7. 发布：换回 `CORE=n` 正式配置 + CRC 闸门 + AK3 打包

## 八、工作方法（必须遵守）
1. **每个补丁必须当场自验证**（`git show --stat` + `grep` 实际内容）—— 今晚发生 6 次"字符串替换未命中却以为改了"
2. **构建产物必须二进制复验**（`strings Image.optNN | grep 新串`）再刷机
3. **每轮 = 改 → 编译 → CRC 4/4 → 刷 → 面包屑测试 → 读现场**（约 5~8 分钟）
4. **重要改动先派子代理审核**（今晚 4 份报告抓到 6 个真问题，含 2 个我自己造的 bug）
5. 用户偏好：**简洁数字中文**；不要让他自己测；出错自动回退保证手机可用

## 九、参考实现与外部资料
- 移植来源：`reigadegr/sun_action::patchs/6.1/6.1sched_ext.diff`（8456 行）
- OPPO 官方 SM8650 补丁：`WildKernels/kernel_patches::oneplus/hmbird/fengchi_OP-ACE-5-PRO_A16.patch`
- Realme GT7 Pro 官方已修 WALT：`realme-kernel-opensource/realme_GT7pro-AndroidB-kernel-source` 的 `walt.c:4794-4821`
- WALT 的 BUG 条件（本机 walt.c 约 5157 行）：`if (!cpumask_test_cpu(new_cpu, p->cpus_ptr)) WALT_BUG(...)`
- 三份子代理报告全文在 `F:\工作区\_audit\`（WSL `/tmp/` 下也有副本）
