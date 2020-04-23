#!/bin/sh

#add wan6 interface for lan
/sbin/uci -q batch <<EOF >/dev/null
set network.wan6=interface
set network.wan6.proto=dhcpv6
set network.wan6.ifname=@wan

commit network
EOF

#check if lan ipv6 is enabled or not
ip6assign=`uci get network.lan.ip6assign 2>/dev/null`
if [ x$ip6assign == "x" ];
then
    uci set network.lan.ip6assign=64
fi

ip6class=`uci get network.lan.ip6class 2>/dev/null`
if [ x$ip6class == "x" ];
then
    uci set network.lan.ip6class="wan6"
fi

#check if guest ipv6 is enabled
guestwifi=`uci get network.guest 2>/dev/null`
ip6assign=`uci get network.guest.ip6assign 2>/dev/null`
if [ x$guestwifi != "x" -a x$ip6assign == "x" ];
then
    uci set network.guest.ip6assign=64
fi

uci commit network


