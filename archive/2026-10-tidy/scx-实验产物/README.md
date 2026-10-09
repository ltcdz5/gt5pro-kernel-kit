# scx（sched_ext）实验产物归档 —— 结论：本机不可用，留作资料

## 结论（两台实测）
真我 GT5 Pro / SM8650 / 6.1.141 厂商分支上，**加载任何 scx 调度器都硬挂死整机**
（无 panic 现场、pstore 0 条、看门狗复位恢复）。
1. 原厂原样加载（调 `scx_bpf_switch_all`）⇒ 挂死；
2. 关掉 `ext.c:2840` 强制全接管 + 换掉 BPF 侧 `switch_all` 调用 ⇒ **依然挂死**
   ⇒ 挂点在 `scx_ops_enable()` 核心（持 `cpus_read_lock` 期间），**不在**批量任务切换。

## 社区调研要点
- 官方 sched-ext/scx **要求内核 ≥ 6.12**；AOSP GKI android14-6.1 / 15-6.6 **都无** sched_ext，只有 android16-6.12 有。
- **没有现成的 6.1 backport**（`scx-backports` 只是用户态 vmlinux.h 适配，非内核补丁）。
- 没找到社区在 Android 真机成功跑标准 scx 的案例。
- **风驰真相**：分 `hmbird`（魔改 sched_ext 调度类，6.1 设备用）与 `hmbird_gki`（sched-walt 钩子，6.6 用）
  ⇒ 风驰**不走 `scx_ops_enable()` 加载 BPF 的路径**；这解释了厂商树里 ext.c 只有"导入+revert"、slim_walt 被剥离。
- **挂死根因高置信**：上游 `efe231d9de`（解耦 enable 三把锁死锁，提交信息明说"不触发 lockdep"，
  完美对应我们无现场硬挂）与 `b06ccbabe2`（enable 线程被切进 ext 后遭 fair 饿死 "hanging the system"），
  **两个修复都在 6.12 之后** ⇒ 厂商这份（2023 v1 时代剥离）一个都没有。

## 入库文件
| 文件 | 说明 |
|---|---|
| `simple.bpf.c.适配本树` | scx_example_simple 适配：① `->scx.` → `->scx->`（本树 scx 是指针）；② 删 `scx_bpf_switch_all()`。需 `-mcpu=v3` 编译。 |
| `scx_setsched.c` | 测试程序：对自己设 `SCHED_EXT=7`，活 30 秒打印 policy，再改回 `SCHED_OTHER` 验证回落。 |

## 大件（不入库，重新生成）
| 文件 | 生成 |
|---|---|
| `vmlinux.h` 3.1MB | `bpftool btf dump file out/vmlinux format c > vmlinux.h`（**勿用 pahole --compile**，匿名 union 重名 bug） |
| `simple.bpf.o` 724KB | 见下方流程 |
| `bpftool_aarch64` 11MB | 官方静态预编译 `bpftool-v7.7.0-arm64.tar.gz`（自带静态 libelf/libz） |
| `scx_setsched` 635KB | `aarch64-linux-gnu-gcc -static -O2 -o scx_setsched scx_setsched.c` |

## BPF 构建流程（可复用；非 scx 的 BPF 实验同样适用且无挂死风险）
```bash
export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH
K=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BPFT=$K/tools/bpf/bpftool/bootstrap/bpftool
mkdir -p /tmp/b && cd /tmp/b
$BPFT btf dump file $K/out/vmlinux format c > vmlinux.h
BD=/tmp/b/asm_inc; mkdir -p $BD/asm
cp -L $K/include/uapi/asm-generic/*.h $BD/asm/; cp -L $K/arch/arm64/include/asm/*.h $BD/asm/
cp $K/tools/sched_ext/scx_example_simple.bpf.c simple.bpf.c
sed -i 's/->scx\./->scx->/g' simple.bpf.c
clang -target bpf -mcpu=v3 -g -O2 -D__TARGET_ARCH_arm64 \
  -I/tmp/b -I$BD -I$K/tools/sched_ext -I$K/tools/sched_ext/tools/include \
  -I$K/tools/sched_ext/tools/include/uapi -I$K/include/uapi -I$K/include \
  -I$K/arch/arm64/include -I$K/tools/lib/bpf -I$K/tools/include -c simple.bpf.c -o simple.bpf.o
llvm-nm simple.bpf.o | grep ' U ' | awk '{print $2}' | sort
```

## 教训
1. ⚠️ 别在这台设备 `struct_ops register` 任何 scx 调度器——必挂死且 pstore 无现场。
2. 厂商这份 ext.c 是被剥离的残缺版；完整实现（含 slim_walt / into_scx 实参）在本仓任何 ref 都不存在。
3. 要"风驰效果"应走 **LSE/slim_walt 模块化路线**（绕开 `scx_ops_enable()`）——本机 `gt5pro-kernel/lse/`
   已有 `lunar_bsp_ext_sched.ko`（1.5MB，Sep 30）可直接试 `insmod`。
