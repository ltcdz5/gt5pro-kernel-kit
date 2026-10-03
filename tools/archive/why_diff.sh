#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo '=== 1) 官方树里有没有 .gitmodules(=代码是"搬到别的仓"而不是"删了") ==='
git show FETCH_HEAD:.gitmodules 2>/dev/null | head -30 || echo '  官方树没有 .gitmodules'
echo '  --- 官方树里 gitlink(子模块指针)条目 ---'
git ls-tree FETCH_HEAD -r | awk '$1=="160000"{print "    ",$4}' | head -20
echo
echo '=== 2) 被"删"的东西在官方树里是否换了地方(换路径=搬家, 找不到=真删) ==='
for k in tcp_brutal ssg-iosched oplus_locking oplus_cpu waker_identify rekernel; do
  n=$(git ls-tree FETCH_HEAD -r --name-only | grep -ic "$k")
  m=$(git ls-tree 7a244ff18 -r --name-only | grep -ic "$k")
  printf '    %-16s 官方树 %2d 个 / cctv18树 %2d 个\n' "$k" "$n" "$m"
done
echo
echo '=== 3) cctv18 顶端那个 Revert 到底revert了什么(看它自己说明了什么) ==='
git show --stat --format='%h%n%s%n%b' 7a244ff18 | head -25
echo
echo '=== 4) 官方 tip 的提交说的是什么内容(它是否本来就只动 OnePlus12 的 vendor 侧) ==='
git log -1 --format='%h %cI%n%s%n%b' FETCH_HEAD | head -12
