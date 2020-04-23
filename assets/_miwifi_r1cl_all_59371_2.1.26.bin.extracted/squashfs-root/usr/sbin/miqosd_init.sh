#!/bin/sh

QOS_FORWARD="miqos_fw"   # for XiaoQiang forward
QOS_INOUT="miqos_io"   # for XiaoQiang input/output
QOS_IP="miqos_id"	# for IP mark
QOS_FLOW="miqos_cg"   # for package flow recognization

IPT="/usr/sbin/iptables -t mangle"
SIP=`uci get network.lan.ipaddr 2>/dev/null`
SMASK=`uci get network.lan.netmask 2>/dev/null`
SIPMASK="$SIP/$SMASK"

guest_SIP=`uci get network.guest.ipaddr 2>/dev/null`
guest_SMASK=`uci get network.guest.netmask 2>/dev/null`
guest_SIPMASK="$guest_SIP/$guest_SMASK"

#路由优先端口，逗号分隔，最多15组，准许iptables-multiport规范
#port: 22 ssh/53 dns/123 ntp/1880:1890 msgagent/5353 mdns/514 syslog-ng
xq_prio_tcp_ports="22,53,80,123,1880:1890,5353"
xq_prio_udp_ports="53,123,514,1880:1890,5353"

#micloud port, 小强源端口,33330~33570 (共计240个端口，TODO:后续可用cgroup统一解决)
xq_micloud_ports="33330:33570"

#清除ipt规则
$IPT -D FORWARD -j $QOS_FORWARD &>/dev/null
$IPT -D INPUT -j $QOS_INOUT &>/dev/null
$IPT -D OUTPUT -j $QOS_INOUT &>/dev/null

#清除QOS规则链
$IPT -F $QOS_FORWARD &>/dev/null
$IPT -X $QOS_FORWARD &>/dev/null

$IPT -F $QOS_INOUT &>/dev/null
$IPT -X $QOS_INOUT &>/dev/null

$IPT -F $QOS_FLOW &>/dev/null
$IPT -X $QOS_FLOW &>/dev/null

$IPT -F $QOS_IP &>/dev/null
$IPT -X $QOS_IP &>/dev/null

#新建QOS规则链
$IPT -N $QOS_FORWARD &>/dev/null
$IPT -N $QOS_FLOW &>/dev/null
$IPT -N $QOS_IP &>/dev/null
$IPT -N $QOS_INOUT &>/dev/null

#连接QOS的几条规则链
$IPT -A FORWARD -j $QOS_FORWARD &>/dev/null
$IPT -A INPUT -j $QOS_INOUT
$IPT -A OUTPUT -j $QOS_INOUT

#构建INOUT的规则框架 {}
if [[ 1 ]]; then
    $IPT -A $QOS_INOUT -j CONNMARK --restore-mark --nfmask 0xffff0000 --ctmask 0xffff0000
    $IPT -A $QOS_INOUT -m mark ! --mark 0/0x000f0000 -j RETURN
    #------------------------------
    #INOUT特定规则
    #APP<->XQ数据流
    $IPT -A $QOS_INOUT -p tcp -m multiport --ports $xq_prio_tcp_ports -j MARK --set-mark 0x00010000/0x000f0000
    $IPT -A $QOS_INOUT -p udp -m multiport --ports $xq_prio_udp_ports -j MARK --set-mark 0x00010000/0x000f0000
    #小强micloud备份源端口,TCP
    $IPT -A $QOS_INOUT -p tcp -m multiport --sports $xq_micloud_ports -j MARK --set-mark 0x00050000/0x000f0000
    cgroup_mark=`lsmod 2>/dev/null|grep xt_cgroup_MARK `
    if [ -n "$cgroup_mark" ]; then
        $IPT -A $QOS_INOUT -j cgroup_MARK --mask 0x000f0000
    fi
    #XQ默认数据类型
    $IPT -A $QOS_INOUT -m mark --mark 0/0x000f0000 -j MARK --set-mark 0x00050000/0x000f0000
    #------------------------------
    $IPT -A $QOS_INOUT -j CONNMARK --save-mark --nfmask 0xffff0000 --ctmask 0xffff0000
fi

#构建FORWARD的规则框架 {}
if [[ 1 ]]; then
    $IPT -A $QOS_FORWARD -j CONNMARK --restore-mark --nfmask 0xffff0000 --ctmask 0xffff0000
    $IPT -A $QOS_FORWARD -m mark ! --mark 0/0xff000000 -j RETURN
    #------------------------------
    #FORWARD特定规则
    $IPT -A $QOS_FORWARD -m mark --mark 0/0xff000000 -j $QOS_IP
    $IPT -A $QOS_FORWARD -m mark --mark 0/0x000f0000 -j flowMARK --ip $SIP --mask $SMASK
    $IPT -A $QOS_FORWARD -m mark --mark 0/0x00f00000 -j $QOS_FLOW
    $IPT -A $QOS_FORWARD -m mark --mark 0/0x000f0000 -j MARK --set-mark 0x00030000/0x000f0000
    #------------------------------
    $IPT -A $QOS_FORWARD -j CONNMARK --save-mark --nfmask 0xffff0000 --ctmask 0xffff0000
fi

#构建IP规则链
if [[ 1 ]]; then
    #构建GUEST网络的IP规则
    if [ -n "$guest_SIP" -a -n "$guest_SMASK" ]; then
        $IPT -A $QOS_IP -d $guest_SIPMASK -j MARK --set-mark-return 0x00f40000/0x00ff0000
        $IPT -A $QOS_IP -s $guest_SIPMASK -j MARK --set-mark-return 0x00f40000/0x00ff0000
    fi

    $IPT -A $QOS_IP -s $SIPMASK -j IP4MARK --addr src
    $IPT -A $QOS_IP -d $SIPMASK -j IP4MARK --addr dst
fi

#构建数据流FLOW规则链
if [[ 1 ]]; then
    CLASS_NUM=4
    for c in $(seq $CLASS_NUM); do
        TCP_PORTS=`uci get miqos.p${c}.tcp_ports 2>/dev/null`
        UDP_PORTS=`uci get miqos.p${c}.udp_ports 2>/dev/null`
        TOS=`uci get miqos.p${c}.tos 2>/dev/null`
        if [ -n "$TCP_PORTS" ]; then
            $IPT -A $QOS_FLOW -p tcp -m mark --mark 0/0xf00000 -m multiport --ports ${TCP_PORTS} -j MARK --set-mark-return 0x${c}00000/0xf00000
        fi
        if [ -n "$UDP_PORTS" ]; then
            $IPT -A $QOS_FLOW -p udp -m mark --mark 0/0xf00000 -m multiport --ports ${UDP_PORTS} -j MARK --set-mark-return 0x${c}00000/0xf00000
        fi
        if [ -n "$TOS" ]; then
            $IPT -A $QOS_FLOW -p udp -m mark --mark 0/0xf00000 -m tos --tos ${TOS} -j MARK --set-mark-return 0x${c}00000/0xf00000
        fi
    done
fi

#since 2015-8-10, content mark startup at init script.
#恒定开启http-content分流功能
#http_content_type_mark.sh on >/dev/null 2>&1

