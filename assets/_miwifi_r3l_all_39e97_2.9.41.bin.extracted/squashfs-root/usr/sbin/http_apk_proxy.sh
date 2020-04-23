#!/bin/sh

CFG_PATH="/proc/sys/net/ipv4/tcp_proxy_action"
LIP=`uci get network.lan.ipaddr 2>/dev/null`
PROXY_PORT=8381
PROXY_SWITCH_PATH="/proc/sys/net/ipv4/tcp_proxy_switch"
APP_CTF_MGR="/usr/sbin/ctf_manger.sh"
service_name="http_apk_proxy"
PIDFILE="/tmp/apk_query.pid"
REFERER_STR="miwifi.com"
REFERER_PATH="/proc/http_conn/referer"

#/usr/sbin/apk_query &
APK_EXECMD="/usr/sbin/apk_query"
APK_EXTRA_FLAG="/usr/sbin/apk_query"

usage()
{
    echo "usage:"
    echo "http_apk_proxy.sh on|off"
    echo "on -- enable apk proxy"
    echo "off -- disable apk proxy"
    echo ""
}

# only for R1CL in china region
is_applicable()
{
    local cc=$(nvram get CountryCode)
    cc=${cc:-"CN"}
    if [ $cc != "CN" ]; then
        echo "http_info.sh: only for China!"
        return 0
    fi
    return 1
}

create_ctf_mgr_entry()
{
    uci -q batch <<EOF > /dev/null
set ctf_mgr.$service_name=service
set ctf_mgr.$service_name.http_switch=off
commit ctf_mgr
EOF
}

reload_iptable_rule()
{
    iptables -t mangle -D fwmark -p tcp --sport 80 -j MARK --set-mark 0x20/0x20
    iptables -t mangle -A fwmark -p tcp --sport 80 -j MARK --set-mark 0x20/0x20
}

add_iptable_rule()
{
    # [R3P] dir: download, skip hwnat
    iptables -t mangle -D fwmark -p tcp --sport 80 -j MARK --set-mark 0x20/0x20
    iptables -t mangle -A fwmark -p tcp --sport 80 -j MARK --set-mark 0x20/0x20

uci -q batch <<-EOF >/dev/null
    set firewall.apk_proxy=include
    set firewall.apk_proxy.path="/lib/firewall.sysapi.loader apk_proxy"
    set firewall.apk_proxy.reload=1
    commit firewall
EOF
}

del_iptable_rule()
{
uci -q batch <<-EOF >/dev/null
    del firewall.apk_proxy
    commit firewall
EOF
    iptables -t mangle -D fwmark -p tcp --sport 80 -j MARK --set-mark 0x20/0x20
}

enable_apk_proxy()
{
    fastpath=`uci get misc.http_proxy.fastpath -q`
    [ -z $fastpath ] && return 0

    if [ $fastpath == "ctf" ]; then
        if [ -f $APP_CTF_MGR ]; then
            is_exist=`uci get ctf_mgr.$service_name -q`
            if [ $? -eq "1" ]; then
                create_ctf_mgr_entry
            fi
            $APP_CTF_MGR $service_name http on
        else
            echo "$service_name: no ctf mgr found!"
            return 0
        fi
    elif [ $fastpath == "hwnat" ]; then
        add_iptable_rule
        echo "$service_name: can work with hw_nat."
    else
        echo "$service_name: unknown fastpath! Treat as std!"
    fi

    # insert kmod
    insmod nf_conn_ext_http >/dev/null 2>&1
    insmod nf_tcp_proxy >/dev/null 2>&1
    insmod http_apk >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null 2>&1

    [ -f $PIDFILE ] && kill $(cat $PIDFILE)


    export PROCLINE="${APK_EXECMD}"
    export PROCFLAG="${APK_EXTRA_FLAG}"
    export PROCNUM='1'
    /usr/sbin/supervisord start
    # ensure start switch
    echo "1" > $PROXY_SWITCH_PATH
    echo "ADD 7 $LIP $PROXY_PORT" > $CFG_PATH
    [ -f $REFERER_PATH ] && echo $REFERER_STR > $REFERER_PATH 2>/dev/null
}

disable_apk_proxy()
{
    rmmod http_apk >/dev/null 2>&1
    rmmod nf_tcp_proxy >/dev/null 2>&1

    export PROCLINE="${APK_EXECMD}"
    export PROCFLAG="${APK_EXTRA_FLAG}"
    /usr/sbin/supervisord stop
    [ -f $PIDFILE ] && kill $(cat $PIDFILE)

    fastpath=`uci get misc.http_proxy.fastpath -q`
    [ -z $fastpath ] && return 0

    if [ $fastpath == "ctf" ]; then
        if [ -f $APP_CTF_MGR ]; then
            $APP_CTF_MGR $service_name http off
        fi
    elif [ $fastpath == "hwnat" ]; then
        del_iptable_rule
        echo "$service_name: stopped."
    else
        echo "$service_name: unknown fastpath! Treat as std!"
    fi
}

op=$1
if [ -z $op ]; then
    usage
    return 0
fi

is_applicable
[ $? -eq 0 ] && return 0

if [ $op == "on" ]; then
    enable_apk_proxy
elif [ $op == "off" ]; then
    disable_apk_proxy
elif [ $op == "reload_iptable_rule" ]; then
    reload_iptable_rule
else
    echo "wrong parameters!"
    usage
fi
return 0
