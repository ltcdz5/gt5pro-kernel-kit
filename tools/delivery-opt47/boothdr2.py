import struct
for tag,p in [('原厂 boot_a','/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot_a.img'),
              ('交付件 opt45-p2','/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-v1.1-opt45-p2-repacked.img')]:
    f=open(p,'rb'); d=f.read(4096); f.close()
    ks,rs,osv,hs = struct.unpack_from('<4I', d, 8)
    hv = struct.unpack_from('<I', d, 40)[0]
    cmd = d[44:44+1536].split(b'\x00')[0].decode('utf-8','replace')
    sig = struct.unpack_from('<I', d, 1580)[0] if hv>=4 else 0
    print('==', tag, '==')
    print('  magic=%s header_version=%d header_size=%d' % (d[:8].decode(), hv, hs))
    print('  kernel_size  = %d' % ks)
    print('  ramdisk_size = %d' % rs)
    print('  os_version   = 0x%08x' % osv)
    print('  v4 signature_size = %d' % sig)
    print('  cmdline      = %s' % cmd[:120])
    print('  ※ v3/v4 头【没有 DTB 字段】：DTB 走 vendor_boot 的 dtb 段或 dtb/dtbo 分区' if hv>=3 else '  ※ v2 头含 dtb_size')
    print()