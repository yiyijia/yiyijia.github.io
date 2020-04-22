---
layout: post
title:  "小米路由器3C (R3L) SSH 开启方法"
date:   2020-04-22 09:23:39 +0800
categories: router
---
# 初衷：
 在串连式双路由器型环境下设置静态路由，奈何小米路由器没提供这个功能，只能开启ssh 手动添加路由器表
# 原理：

  利用 远程命令执行漏洞（CVE-2019-18370）root权限 , 具体是 /api/xqnetdetect/netspeed 存在命令注入漏洞 , 远程执行脚本如下
  ```bash
nvram set ssh_en=1; nvram commit ;
sed -i ';:x:N:s/if \[.*\; then\n.*return 0\n.*fi/#tb/;b x'; /etc/init.d/dropbear 
/etc/init.d/dropbear start
(echo 'admin'; sleep 1; echo 'admin') | passwd 'root' >/dev/null 2>&1
  ```
### 工具
1. 固件：[miwifi_r3l_firmware_a5c81_2.9.217.bin]
2. python3
3. 脚本: [remote_command_execution_vulnerability.py]



# 步骤：
1. 执行 python3 remote_command_execution_vulnerability.py ,输入 stok (来源于路由器登录后url)
{% highlight bash %}
% python3 remote_command_execution_vulnerability.py 
stok: 03b2da2xxxxx
{% endhighlight %}

2. 执行后 就应该能登录了, ssh root/admin
   `ssh root@192.168.31.1 `

# 折腾过程
1. mini r1l 漏洞 set_router_wifiap ,binwalk 查看源码发现已封堵
2. 小米路由器的nginx配置文件错误，导致目录穿越漏洞, 结果 404, 已封堵
3. 使用 miwifi_r3_all_55ac7_2.11.20.bin 固件，文件太大 无法升级固件，r3l NorFlash内存大小 16M
4. 自定义固件,binwalk 解压固件，修改lua, dd切分，squashfs打包，发现公钥校验rom, 此路不通
5. 使用ttl(非编程器),uart_en=0 无法输入, 此路不通

# Q&A
大家如果有问题 可以提issue 到 [howblog github]

# 参考: 
1. [Xiaomi_Mi_WiFi_R3G_Vulnerability_POC]
2. [SSH开启命令]
3. [CVE-2019-18370]



[SSH开启命令]: https://www.jianshu.com/p/37d0aa13614c
[CVE-2019-18370]:   https://github.com/UltramanGaia/Xiaomi_Mi_WiFi_R3G_Vulnerability_POC/blob/master/report/report.md
[Xiaomi_Mi_WiFi_R3G_Vulnerability_POC]: https://github.com/UltramanGaia/Xiaomi_Mi_WiFi_R3G_Vulnerability_POC
[miwifi_r3l_firmware_a5c81_2.9.217.bin]: /assets/miwifi_r3l_firmware_a5c81_2.9.217.bin
[remote_command_execution_vulnerability.py]:/assets/remote_command_execution_vulnerability.py
[howblog github]: https://github.com/mysansa52/howblog.github.io/issues