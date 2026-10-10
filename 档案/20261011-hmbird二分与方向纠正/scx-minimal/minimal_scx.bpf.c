/* minimal_scx.bpf.c — minimal struct_ops sched_ext scheduler (hello world)
 *
 * 目标内核：/home/builder/kwork/wt-core 编出的 opt 系列（OPPO hmbird fork 的 sched_ext，
 *           struct sched_ext_ops 共 23 个 ops 成员 + dispatch_max_batch/flags/timeout_ms/name[128]，
 *           总大小 336 字节）。
 *
 * 自包含：只需要 vmlinux.h（由目标内核 BTF 生成）：
 *     bpftool btf dump file /home/builder/kwork/out-core/vmlinux format c > vmlinux.h
 * 不要 include <bpf/bpf_helpers.h>（本机没装 libbpf-dev；树内那份依赖构建期生成的
 * bpf_helper_defs.h）。
 *
 * 编译（已实测 rc=0）：
 *     clang -target bpf -D__TARGET_ARCH_arm64 -O2 -g -c minimal_scx.bpf.c -o minimal_scx.bpf.o -I.
 * 注册（设备侧，需 aarch64 版 bpftool）：
 *     bpftool struct_ops register minimal_scx.bpf.o
 * 退出：
 *     kill 掉 bpftool / 或 echo s > /proc/sysrq-trigger（reset-sched-ext，需 sysrq 含 0x100 位）
 */
#include "vmlinux.h"

#define SEC(name) __attribute__((section(name), used))
#define __ksym    __attribute__((section(".ksyms")))

char _license[] SEC("license") = "GPL";

/* 本内核常量：定义在 include/linux/sched/ext.h 的 enum 里，vmlinux.h 不带 */
#define SCX_DSQ_FLAG_BUILTIN  (1ULL << 63)
#define SCX_DSQ_FLAG_LOCAL_ON (1ULL << 62)
#define SCX_DSQ_GLOBAL        (SCX_DSQ_FLAG_BUILTIN | 1)
#define SCX_DSQ_LOCAL         (SCX_DSQ_FLAG_BUILTIN | 2)
#define SCX_SLICE_DFL         (20ULL * 1000000)

extern void scx_bpf_dispatch(struct task_struct *p, __u64 dsq_id, __u64 slice, __u64 enq_flags) __ksym;
extern bool scx_bpf_consume(__u64 dsq_id) __ksym;

SEC("struct_ops/minimal_select_cpu")
__s32 minimal_select_cpu(struct task_struct *p, __s32 prev_cpu, __u64 wake_flags)
{
	return prev_cpu;
}

SEC("struct_ops/minimal_enqueue")
void minimal_enqueue(struct task_struct *p, __u64 enq_flags)
{
	scx_bpf_dispatch(p, SCX_DSQ_GLOBAL, SCX_SLICE_DFL, enq_flags);
}

SEC("struct_ops/minimal_dispatch")
void minimal_dispatch(__s32 cpu, struct task_struct *prev)
{
	scx_bpf_consume(SCX_DSQ_GLOBAL);
}

SEC(".struct_ops.link")
struct sched_ext_ops minimal_ops = {
	.select_cpu = (void *)minimal_select_cpu,
	.enqueue    = (void *)minimal_enqueue,
	.dispatch   = (void *)minimal_dispatch,
	.name       = "minimal",
};
