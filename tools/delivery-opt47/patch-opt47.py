import io
K='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
p=K+'drivers/i2c/i2c-core-base.c'
s=io.open(p,encoding='utf-8').read()
# ---- 修 A1: idr_alloc 改存 NULL（两处）----
a1='idr_alloc(&i2c_adapter_idr, adap, adap->nr, adap->nr + 1, GFP_KERNEL)'
assert s.count(a1)==1, 'A1 anchor=%d' % s.count(a1)
s=s.replace(a1, a1.replace(', adap,', ', NULL,'), 1)
a2='idr_alloc(&i2c_adapter_idr, adapter,'
assert s.count(a2)==1, 'A2 anchor=%d' % s.count(a2)
s=s.replace(a2, 'idr_alloc(&i2c_adapter_idr, NULL,', 1)
# ---- 修 A2: 在 device_register 前发布真指针 ----
old_dr = 'adap->dev.type = &i2c_adapter_type;' + chr(10) + chr(9) + 'res = device_register(&adap->dev);'
assert s.count(old_dr)==1, 'A3 anchor=%d' % s.count(old_dr)
new_dr = ('adap->dev.type = &i2c_adapter_type;' + chr(10) + chr(10) +
  chr(9) + '/*' + chr(10) +
  chr(9) + ' * opt47: 公布适配器指针。id 在 i2c_add_adapter()/__i2c_add_numbered_adapter()' + chr(10) +
  chr(9) + ' * 里先用 NULL 占位保留，只有到这里——适配器已完全初始化——才把真实指针写进 idr，' + chr(10) +
  chr(9) + ' * 避免别的线程在注册中途用 i2c_get_adapter() 拿到半成品适配器。' + chr(10) +
  chr(9) + ' * 对应 ACK 1febb174815b (i2c: core: fix adapter registration race)。' + chr(10) +
  chr(9) + ' */' + chr(10) +
  chr(9) + 'mutex_lock(&core_lock);' + chr(10) +
  chr(9) + 'idr_replace(&i2c_adapter_idr, adap, adap->nr);' + chr(10) +
  chr(9) + 'mutex_unlock(&core_lock);' + chr(10) + chr(10) +
  chr(9) + 'res = device_register(&adap->dev);')
s=s.replace(old_dr, new_dr, 1)
# ---- 修 B1: dev_set_name 判返回值 ----
old_dsn = chr(9) + 'dev_set_name(&adap->dev, "i2c-%d", adap->nr);'
assert s.count(old_dsn)==1, 'B1 anchor=%d' % s.count(old_dsn)
new_dsn = (chr(9) + 'res = dev_set_name(&adap->dev, "i2c-%d", adap->nr);' + chr(10) +
  chr(9) + 'if (res) {' + chr(10) +
  chr(9) + chr(9) + 'pr_err("adapter \'%s\': can\'t set device name (%d)\\n", adap->name, res);' + chr(10) +
  chr(9) + chr(9) + 'goto err_remove_irq_domain;' + chr(10) +
  chr(9) + '}')
s=s.replace(old_dsn, new_dsn, 1)
# ---- 修 B2: device_register 失败改走 teardown 路径 ----
old_pr = chr(9) + 'pr_err("adapter \'%s\': can\'t register device (%d)\\n", adap->name, res);' + chr(10) + chr(9) + 'goto out_list;'
assert s.count(old_pr)==1, 'B2 anchor=%d' % s.count(old_pr)
s=s.replace(old_pr, old_pr.replace('goto out_list;','goto err_remove_irq_domain;'), 1)
# ---- 修 B3: 新增 err_remove_irq_domain 标签 ----
old_lbl = 'out_list:' + chr(10) + chr(9) + 'mutex_lock(&core_lock);'
assert s.count(old_lbl)==1, 'B3 anchor=%d' % s.count(old_lbl)
new_lbl = ('err_remove_irq_domain:' + chr(10) +
  chr(9) + '/* opt47: 失败路径补拆 Host Notify IRQ domain（ACK e984010cda7d 的附带收益，未取它的 debugfs 结构体改动）*/' + chr(10) +
  chr(9) + 'i2c_host_notify_irq_teardown(adap);' + chr(10) +
  'out_list:' + chr(10) + chr(9) + 'mutex_lock(&core_lock);')
s=s.replace(old_lbl, new_lbl, 1)
io.open(p,'w',encoding='utf-8').write(s)
print('i2c-core-base.c 已按 opt47 方案修改（A 竞态 3 处 + B 失败路径 3 处）')