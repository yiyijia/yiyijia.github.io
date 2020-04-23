#!/bin/sh

LIP=`uci -q get network.lan.ipaddr`
LMASK=`uci -q get network.lan.netmask`
WEBFILTER_SBIN="/usr/sbin/webfilter_config"
REFERER_CFG_FILE="/proc/sys/net/ipv4/http_match_warn_page"
REFERER_IGNORE="http://api.miwifi.com/"
L_WARNING_PORT=8192
PROXY_CFG_PATH="/proc/sys/net/ipv4/tcp_proxy_action"
PROXY_SWITCH_PATH="/proc/sys/net/ipv4/tcp_proxy_switch"
SEC_SWITCH_PATH="/proc/sys/net/ipv4/http_security_switch"

# only for lite in china region
is_applicable()
{
    local cc=$(bdata get CountryCode)
    cc=${cc:-"CN"}
    if [ $cc != "CN" ]; then
        echo "security_cfg: only for China!"
        return 0
    fi

    if [ ! -f $WEBFILTER_SBIN ]; then
        echo "security_cfg: $WEBFILTER_SBIN not exist!"
        return 0
    fi

    #local dev_model=$(uci -q -c /usr/share/xiaoqiang get xiaoqiang_version.version.HARDWARE)
    #if [ $dev_model != "R1CL" -a $dev_model != "R3L" ]; then
    #    echo "security_cfg: only for Lite version!"
    #    return 0
    #fi
    return 1
}

usage()
{
    echo "security_cfg.sh on|off"
    echo "on -- enable security query"
    echo "off -- disable security query"
    echo ""
}

enable_security_query()
{
    # insert kmod
    insmod nf_conn_ext_http >/dev/null 2>&1
    insmod nf_tcp_proxy >/dev/null 2>&1
    insmod http_match >/dev/null 2>&1
    # disable timestamps
    sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null 2>&1

    # kernel config
    $WEBFILTER_SBIN -s $LIP/$LMASK >/dev/null 2>&1
    if [ -f $REFERER_CFG_FILE ]; then
        echo $REFERER_IGNORE > $REFERER_CFG_FILE
    else
        echo "security_cfg: $REFERER_CFG_FILE not exist."
        return 0
    fi
    echo "ADD 1 $LIP $L_WARNING_PORT" > $PROXY_CFG_PATH

    # ensure start switch
    echo "1" > $PROXY_SWITCH_PATH
    echo "1" > $SEC_SWITCH_PATH
}

disable_security_query()
{
    rmmod http_match >/dev/null 2>&1
    rmmod nf_tcp_proxy >/dev/null 2>&1
}

op=$1
if [ -z $op ]; then
    usage
    return 0
fi

is_applicable
[ $? -eq 0 ] && return 0

if [ $op == "on" ]; then
    enable_security_query
elif [ $op == "off" ]; then
    disable_security_query
else
    usage
fi
return 0
