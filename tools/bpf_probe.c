#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <linux/bpf.h>
#include <sys/syscall.h>

static int sys_bpf(int cmd, union bpf_attr *a, unsigned sz)
{
	return (int)syscall(__NR_bpf, cmd, a, sz);
}

int main(void)
{
	union bpf_attr at;

	printf("getuid=%d geteuid=%d pid=%d\n", getuid(), geteuid(), getpid());

	/* 1) 最基础: 建一个 array map —— 只考 bpf() 权限 */
	memset(&at, 0, sizeof(at));
	at.map_type = BPF_MAP_TYPE_ARRAY;
	at.key_size = sizeof(__u32);
	at.value_size = sizeof(__u32);
	at.max_entries = 1;
	int m = sys_bpf(BPF_MAP_CREATE, &at, sizeof(at));
	printf("BPF_MAP_CREATE : %s (fd=%d errno=%d %s)\n",
	       m >= 0 ? "OK" : "FAIL", m, errno, strerror(errno));

	/* 2) 程序加载: 一条 exit 0 的指令 —— 考能不能往内核里塞代码 */
	struct bpf_insn prog[2] = {
		{ .code = BPF_ALU64 | BPF_MOV | BPF_K, .dst_reg = 0, .imm = 0 },
		{ .code = BPF_JMP | BPF_EXIT },
	};
	memset(&at, 0, sizeof(at));
	at.prog_type = BPF_PROG_TYPE_SOCKET_FILTER;
	at.insn_cnt = 2;
	at.insns = (__aligned_u64)(unsigned long)prog;
	at.license = (__aligned_u64)(unsigned long)"GPL";
	at.log_level = 0;
	int p = sys_bpf(BPF_PROG_LOAD, &at, sizeof(at));
	printf("BPF_PROG_LOAD  : %s (fd=%d errno=%d %s)\n",
	       p >= 0 ? "OK" : "FAIL", p, errno, strerror(errno));

	/* 3) 关键闸: 能不能建 STRUCT_OPS 类型的 map —— scx 注册就靠它
	   参数不全没关系, 看 errno: EPERM/EACCES=被拦(权限/SELinux),
	   EINVAL=通道开着、只是我给的参数不对(这才是好消息) */
	memset(&at, 0, sizeof(at));
	at.map_type = BPF_MAP_TYPE_STRUCT_OPS;
	at.value_size = 8;
	at.max_entries = 1;
	int b = sys_bpf(BPF_MAP_CREATE, &at, sizeof(at));
	printf("STRUCT_OPS_MAP : %s (fd=%d errno=%d %s)  <EPERM=被拦 / EINVAL=通道通、参数不对>\n",
	       b >= 0 ? "OK" : "FAIL", b, errno, strerror(errno));

	if (m >= 0) close(m);
	if (p >= 0) close(p);
	return 0;
}
