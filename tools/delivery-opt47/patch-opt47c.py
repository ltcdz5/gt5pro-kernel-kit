import io
K='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/'
p=K+'drivers/i2c/i2c-core-base.c'
s=io.open(p,encoding='utf-8').read()
TAB=chr(9)
# A1: __i2c_add_numbered_adapter 的 idr_alloc 改存 NULL
a1='idr_alloc(&i2c_adapter_idr, adap, adap->nr, adap->nr + 1, GFP_KERNEL)'
print('A1 =', s.count(a1)); assert s.count(a1)==1
s=s.replace(a1, 'idr_alloc(&i2c_adapter_idr, NULL, adap->nr, adap->nr + 1, GFP_KERNEL)', 1)
# A2: i2c_add_adapter 的 idr_alloc 改存 NULL
a2='idr_alloc(&i2c_adapter_idr, adapter,'
print('A2 =', s.count(a2)); assert s.count(a2)==1
s=s.replace(a2, 'idr_alloc(&i2c_adapter_idr, NULL,', 1)
# A3: device_register 前发布真指针
old_a3 = TAB+'adap->dev.type = &i2c_adapter_type;' + chr(10) + TAB + 'res = device_register(&adap->dev);'
print('A3 =', s.count(old_a3)); assert s.count(old_a3)==1
new_a3 = (TAB+'adap->dev.type = &i2c_adapter_type;' + chr(10) + chr(10) +
  TAB+'/*' + chr(10) +
  TAB+' * opt47：公布适配器指针。id 在 i2c_add_adapter()/__i2c_add_numbered_adapter() 里' + chr(10) +
  TAB+' * 先用 NULL 占位保留，到这里——适配器已完全初始化——才把真实指针写进 idr，避免别的线程' + chr(10) +
  TAB+' * 在注册中途用 i2c_get_adapter() 拿到半成品适配器。' + chr(10) +
  TAB+' * 对应 ACK 1febb174815b（i2c: core: fix adapter registration race）。' + chr(10) +
  TAB+' */' + chr(10) +
  TAB+'mutex_lock(&core_lock);' + chr(10) +
  TAB+'idr_replace(&i2c_adapter_idr, adap, adap->nr);' + chr(10) +
  TAB+'mutex_unlock(&core_lock);' + chr(10) + chr(10) +
  TAB+'res = device_register(&adap->dev);')
s=s.replace(old_a3, new_a3, 1)
# B1: dev_set_name 判返回值
old_b1 = TAB+'dev_set_name(&adap->dev, "i2c-%d", adap->nr);'
print('B1 =', s.count(old_b1)); assert s.count(old_b1)==1
new_b1 = (TAB+'res = dev_set_name(&adap->dev, "i2c-%d", adap->nr);' + chr(10) +
  TAB+'if (res) {' + chr(10) +
  TAB+TAB+'pr_err("adapter \'%s\': can\'t set device name (%d)\\n", adap->name, res);' + chr(10) +
  TAB+TAB+'goto err_remove_irq_domain;' + chr(10) +
  TAB+'}')
s=s.replace(old_b1, new_b1, 1)
io.open(p,'w',encoding='utf-8').write(s)
print('A1/A2/A3/B1 已应用')