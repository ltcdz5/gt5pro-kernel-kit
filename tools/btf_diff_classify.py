# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/btf_diff_classify.py
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；如派生/借鉴第三方，逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节（KernelSU / SUSFS / lz4-zstd 补丁 / SSG / AnyKernel3 /
#            UY-Scuti / libbpf-bpftool / sched-ext / LunarKernel LSE 等）
# ---------------------------------------------------------------------------
import re, subprocess, collections
FULL='/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/vendor-ko-symbols.txt'
T='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
diff=subprocess.run(['diff','/home/builder/abi/full/opt11.txt','/home/builder/abi/full/opt12.txt'],capture_output=True,text=True).stdout
# 取差异里出现的成员名, 再回到 opt12 全文里找它所属的 struct 名
lines=[l for l in diff.splitlines() if l[:1] in '<>']
mem=[]
for l in lines:
    m=re.search(r'^[<>]\s+[\w *]+?\b(\w+);\s+/\*\s+(\d+)\s+(\d+)\s*\*/', l)
    if m: mem.append(m.group(1))
txt=open('/home/builder/abi/full/opt12.txt',encoding='utf-8',errors='replace').read().splitlines()
structs=[]
for target in set(mem):
    for i,l in enumerate(txt):
        if re.search(r'\b'+re.escape(target)+r';\s+/\*', l):
            for j in range(i,-1,-1):
                m=re.match(r'^(struct|union|enum)\s+(\w+)\s*\{', txt[j])
                if m:
                    if m.group(2) not in structs: structs.append(m.group(2))
                    break
            break
print("差异涉及的成员名 %d 个 → 归属结构体 %d 个:" % (len(set(mem)), len(structs)))
for s in structs: print("   ", s)
print()
vko=set(open(FULL,encoding='utf-8',errors='replace').read().split())
print("逐个判: 是否在头文件里定义(=外部可见) / 是否被厂商 .ko 引用名命中")
for s in structs:
    inhdr=subprocess.run(['grep','-rls','-E',r'\b'+s+r'\s*\{',T+'include',T+'net',T+'fs',T+'mm'],capture_output=True,text=True).stdout.strip().splitlines()
    inhdr=[h for h in inhdr if h.endswith('.h')]
    hit = s in vko
    print("  %-26s 头文件定义=%-3s  厂商引用命中=%s" % (s, ('是:'+inhdr[0].replace(T,'') if inhdr else '否(仅在.c)'), '⛔有' if hit else '无'))
