#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sched.h>

/* SCHED_EXT = 7（本树 include/uapi/linux/sched.h:121） */
#define SCX_POL 7

int main(int argc, char **argv) {
    struct sched_param p;
    memset(&p, 0, sizeof(p));
    p.sched_priority = 0;

    int old = sched_getscheduler(0);
    printf("current policy = %d\n", old);

    int r = sched_setscheduler(0, SCX_POL, &p);
    printf("sched_setscheduler(SCHED_EXT=%d) = %d", SCX_POL, r);
    if (r != 0) { printf(" errno=%s", strerror(errno)); }
    printf("\n");
    if (r != 0) return 1;

    int now = sched_getscheduler(0);
    printf("policy now = %d %s\n", now, now == SCX_POL ? "(在 ext 类)" : "(未进入!)");

    /* 活 30 秒，期间每 2 秒报一次策略，证明被调度 */
    for (int i = 0; i < 15; i++) {
        usleep(2000000);
        printf("alive %2d policy=%d\n", i, sched_getscheduler(0));
        fflush(stdout);
    }

    /* 改回 SCHED_OTHER(0)，验证回落 */
    p.sched_priority = 0;
    r = sched_setscheduler(0, SCHED_OTHER, &p);
    printf("back to OTHER = %d, policy now = %d\n", r, sched_getscheduler(0));
    return 0;
}
