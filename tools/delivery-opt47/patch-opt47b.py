import io
K='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
p=K+'drivers/i2c/i2c-core-base.c'
s=io.open(p,encoding='utf-8').read()
TAB=chr(9)
# B2: device_register 失败改走 teardown 路径（注意：pr_err/goto 是两个 TAB）
old_b2 = TAB+TAB+'pr_err("adapter \'%s\': can\'t register device (%d)\\n", adap->name, res);' + chr(10) + TAB+TAB+'goto out_list;'
print('B2 anchor 命中 =', s.count(old_b2))
assert s.count(old_b2)==1
s = s.replace(old_b2, old_b2.replace('goto out_list;','goto err_remove_irq_domain;'), 1)
# B3: 新增 err_remove_irq_domain 标签
old_b3 = 'out_list:' + chr(10) + TAB + 'mutex_lock(&core_lock);'
print('B3 anchor 命中 =', s.count(old_b3))
assert s.count(old_b3)==1
new_b3 = ('err_remove_irq_domain:' + chr(10) +
  TAB + '/* opt47: 失败路径补拆 Host Notify IRQ domain（取自 ACK e984010cda7d 的附带收益；' + chr(10) +
  TAB + ' * 未取它的 debugfs 结构体改动，因为那会给 struct i2c_adapter 加成员而影响导出符号 CRC）*/' + chr(10) +
  TAB + 'i2c_host_notify_irq_teardown(adap);' + chr(10) +
  'out_list:' + chr(10) + TAB + 'mutex_lock(&core_lock);')
s = s.replace(old_b3, new_b3, 1)
io.open(p,'w',encoding='utf-8').write(s)
print('B2/B3 已应用')