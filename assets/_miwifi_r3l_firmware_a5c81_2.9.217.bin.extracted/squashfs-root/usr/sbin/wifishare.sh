#!/bin/sh
# Copyright (C) 2016 Xiaomi
. /lib/functions.sh

network_name="guest"
section_name="wifishare"
redirect_port="8999"
dev_redirect_port="8899"
whiteport_list="67 68"
http_port="80"
dns_port="53"
dnsd_port="5533"
dnsd_conf="/var/dnsd.conf"
guest_gw=""
fw3lock="/var/run/fw3.lock"

hasctf=$(uci get misc.quickpass.ctf 2>/dev/null)
guest_ifname=$(uci get wireless.guest_2G.ifname 2>/dev/null)
hashwnat=$([ -f /etc/init.d/hwnat ] && echo 1)
auth_timeout_default=90
timeout_default=86400
date_tag=$(date +%F" "%H:%M:%S)
macs_blocked=""

share_block_table="wifishare_block"
share_block_table_input="wifishare_block_input"

share_whitehost_ipset="wifishare_whitehost"
share_whitehost_file="/etc/dnsmasq.d/wifishare_whitehost.conf"

share_nat_table="wifishare_nat"
share_filter_table="wifishare_filter"
share_nat_device_table="wifishare_nat_device"
share_filter_device_table="wifishare_filter_device"
share_nat_dev_redirect_table="wifishare_nat_dev_redirect"

hosts_dianping=".dianping.com .dpfile.com"
hosts_apple=""
hosts_nuomi=""
hosts_index="dianping"
filepath=$(cd `dirname $0`; pwd)
filename=$(basename $0;)

daemonfile="/usr/sbin/wifishare_daemon.sh"

active="user business"
#wechat qq dianping nuomi .etc
active_type=""

WIFIRENT_NAME="wifirent"
TICKET_NAME="ticket"
COUNT_INTERVAL=5  #Minites
COUNT_INTERVAL_SECS=300 #1 minites
MATOOL_DATA_FILE="/tmp/wifishare.remote.log"
COUNTING_DATA_FILE="/tmp/wifishare.counting.log"
counting_pid="/tmp/wifishare_counting.pid"

################### domain list #############

wifishare_log()
{
    logger -p warn -t wifishare "$1"
}

business_whitehost_add()
{
    for _host in $1
    do
        echo "ipset=/$_host/$share_whitehost_ipset" >>$share_whitehost_file
    done
}

business_init()
{
    rm $share_whitehost_file
    touch $share_whitehost_file

    for _idx in $hosts_index
    do
        _hosts=`eval echo '$hosts_'"$_idx"`
        business_whitehost_add "$_hosts"
    done
}

################### hwnat ###################
hwnat_start()
{
    [ "$hashwnat" != "1" ] && return;

uci -q batch <<-EOF >/dev/null
    set hwnat.switch.${section_name}=0
    commit hwnat
EOF
    /etc/init.d/hwnat start &>/dev/null
}

hwnat_stop()
{
    [ "$hashwnat" != "1" ] && return;

uci -q batch <<-EOF >/dev/null
    set hwnat.switch.${section_name}=1
    commit hwnat
EOF
    /etc/init.d/hwnat stop &>/dev/null
}

_locked="0"
################### lock ###################
fw3_lock()
{
    trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
    lock $fw3lock
    return $?
}

fw3_trylock()
{
    trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
    lock -n $fw3lock
    [ $? == 1 ] && _locked="1"
    return $?
}

fw3_unlock()
{
    lock -u $fw3lock
}

################### dnsd ###################
share_dnsd_start()
{

    killall dnsd > /dev/null 2>&1

    guest_gw=$(uci get network.guest.ipaddr)
    [ $? != 0 ] && return;

    #always create/update the dnsd config file (guest gw maybe changed)
    echo "* $guest_gw" > $dnsd_conf
    [ $? != 0 ] && return;

    dnsd -p $dnsd_port -c $dnsd_conf -d > /dev/null 2>&1
    [ $? != 0 ] && {
        rm $dnsd_conf > /dev/null 2>&1
        return ;
    }
}

share_dnsd_stop()
{
    killall dnsd > /dev/null 2>&1

    [ -f $dnsd_conf ] && {
        rm $dnsd_conf > /dev/null 2>&1
    }
}

################### config ###################


share_parse_global()
{
    local section="$1"
    auth_timeout=""
    timeout=""

    config_get disabled  $section disabled &>/dev/null;

    #config_get auth_timeout  $section auth_timeout &>/dev/null;
    [ "$auth_timeout" == "" ] && auth_timeout=${auth_timeout_default}

    config_get timeout  $section timeout &>/dev/null;
    [ "$timeout" == "" ] && timeout=${timeout_default}

    config_get _business  $section business &>/dev/null;
    [ "$_business" == "" ] && _business=${business_default}

    config_get _sns  $section sns &>/dev/null;
    [ "$_sns" == "" ] && _sns=${sns_default}

    config_get _active  $section active &>/dev/null;
    [ "$_active" == "" ] && _active=${active_default}

    if [ "$_active" == "business" ]
    then
        active_type="$_business"
    else
        active_type="$_sns"
    fi

    #echo "active   -- $_active"
    #echo "sns      -- $_sns"
    #echo "business -- $_business"
    #echo "type     -- $active_type"
}

share_parse_block()
{
    config_get macs_blocked $section mac &>/dev/null;
}


share_ipset_create()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1
    ipset create  $_rule_ipset hash:net >/dev/null

    return
}


share_ipset_destroy()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1

    return
}

################### iptables ###################
ipt_table_create()
{
    iptables -t $1 -F $2 >/dev/null 2>&1
    iptables -t $1 -X $2 >/dev/null 2>&1
    iptables -t $1 -N $2 >/dev/null 2>&1
}

ipt_table_destroy()
{
    iptables -t $1 -F $2 >/dev/null 2>&1
    iptables -t $1 -X $2 >/dev/null 2>&1
}

################### firewall ###################
share_fw_add_default()
{
    [ "$hasctf" == "1" ] && iptables -t mangle -I PREROUTING -i br-guest  -j SKIPCTF

    ipt_table_create nat     $share_nat_table
    ipt_table_create nat     $share_nat_device_table
    ipt_table_create nat     $share_nat_dev_redirect_table
    ipt_table_create filter  $share_filter_table
    ipt_table_create filter  $share_filter_device_table

    iptables -t nat -I zone_guest_prerouting -i br-guest -j $share_nat_table >/dev/null 2>&1
    iptables -t filter -I forwarding_rule -i br-guest -j $share_filter_table >/dev/null 2>&1

    iptables -t nat -A $share_nat_table -p tcp -j REDIRECT --to-ports ${redirect_port}
    iptables -t nat -A $share_nat_table -p udp -j REDIRECT --to-ports ${redirect_port}

    #dns redirect
    local dnsd_ok="0"
    ps | grep dnsd | grep -v grep >/dev/null 2>&1
    [ $? == 0 ] && {
        dnsd_ok="1"
    }

    [ "$dnsd_ok" == "1" ] && {
        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${dns_port} -j REDIRECT --to-port ${dnsd_port}
    }

    #device list
    iptables -t filter -I $share_filter_table -j $share_filter_device_table
    iptables -t nat -I $share_nat_table -j $share_nat_device_table


    if [ "$dnsd_ok" == "1" ];
    then
        iptables -t nat -I $share_nat_dev_redirect_table -j ACCEPT
        echo a1
        iptables -t nat -I $share_nat_dev_redirect_table -p tcp --dst ${guest_gw} --dport ${http_port} -j REDIRECT --to-ports ${dev_redirect_port}
        echo a2
        iptables -t nat -I $share_nat_dev_redirect_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
    else
        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${dns_port} -j ACCEPT
    fi

    for _port in ${whiteport_list}
    do
        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${_port} -j ACCEPT
    done


    #white host
    iptables -t filter -I $share_filter_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
    iptables -t nat -I $share_nat_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
}

is_active_type()
{
#　$1 type
# $2 type list
    local _type=""
    [ "$1" == "" ] && return 1;
    [ "$2" == "" ] && return 1;

    #reload
    local _is_wechat_pay=$(echo $2 | grep "wifirent_wechat_pay")
    [ "$_is_wechat_pay" != "" ] && {
        [ "$1" == "$WIFIRENT_NAME" ] && return 0;
    }

    #wifishare enable
    [ "$1" == "$WIFIRENT_NAME" ] && return 0;

    for _type in $2
    do
        [ "$_type" == "$1" ] && return 0;
    done

    return 1;
}

share_fw_add_device()
{
    local section="$1"
    local _src_mac=""
    local _start=""
    local _stop=""

    config_get disabled $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get _start $section datestart &>/dev/null;
    [ "$_start" == "" ] && return

    config_get _stop $section datestop &>/dev/null;
    [ "$_stop" == "" ] && return

    config_get _src_mac $section mac &>/dev/null;
    [ "$_src_mac" == "" ] && return

    config_get _type $section sns &>/dev/null;
    [ "$_type" == "" ] && return

    is_active_type "$_type" "$active_type" || return;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    share_access_remove $_src_mac

    iptables -t filter -A $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP   >/dev/null 2>&1
    iptables -t nat    -I $share_nat_device_table    -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT >/dev/null 2>&1

    return;
}

share_fw_add_device_all()
{
    config_load ${section_name}

    config_foreach share_fw_add_device device

    return;
}

share_fw_remove_all()
{
    [ "$hasctf" == "1" ] && iptables -t mangle -D PREROUTING -i br-guest  -j SKIPCTF

    iptables -t nat -D zone_guest_prerouting -i br-guest -j $share_nat_table >/dev/null 2>&1

    iptables -t filter -D forwarding_rule  -i br-guest -j $share_filter_table >/dev/null 2>&1

    ipt_table_destroy nat     $share_nat_table
    ipt_table_destroy nat     $share_nat_device_table
    ipt_table_destroy nat     $share_nat_dev_redirect_table
    ipt_table_destroy filter  $share_filter_table
    ipt_table_destroy filter  $share_filter_device_table

    return
}
################### contrack ###################
share_contrack_remove_perdevice()
{
    local section="$1"
    local _src_mac=""
    local _start=""
    local _stop=""

    config_get _src_mac $section mac &>/dev/null;
    [ "$_src_mac" == "" ] && return

    share_contrack_remove $_src_mac

    return
}

share_contrack_remove_all()
{
    config_load ${section_name}

    config_foreach share_contrack_remove_perdevice device

    return
}

share_contrack_remove()
{
    local _ip=$(/usr/bin/arp | awk -v mac=$1 ' BEGIN{IGNORECASE=1}{if($3==mac) print $1;}' 2>/dev/null)

    [ "$_ip" == "" ] && return

    echo $_ip > /proc/net/nf_conntrack
    return
}

################### block ###################
share_block_has_mac()
{
    local _src_mac=$1
    local has_mac=""

    [ "$_active" == "business" ] && return 0

    [ "$macs_blocked"  == "" ] && return 0

    has_mac=$(echo $macs_blocked | awk -v mac=$_src_mac '{for(i=1;i<=NF;i++) { if($i==mac) print "1"; break;} }')

    [ "$has_mac" != "" ] && return 1

    return 0;
}

share_block_add_default()
{
    share_block_remove_default

    ipt_table_create filter $share_block_table
    ipt_table_create filter $share_block_table_input

    iptables -t filter -I forwarding_rule -i br-guest -j $share_block_table >/dev/null 2>&1
    iptables -t filter -I INPUT -i br-guest -j $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT
}

share_block_remove_default()
{
    iptables -t filter -D forwarding_rule -i br-guest -j $share_block_table >/dev/null 2>&1
    iptables -t filter -D INPUT -i br-guest -j $share_block_table_input >/dev/null 2>&1

    ipt_table_destroy filter $share_block_table
    ipt_table_destroy filter $share_block_table_input
}

share_block_add_perdevice()
{
    local section="$1"
    local _src_mac=""

    config_get _mac_list $section mac &>/dev/null;

    for _src_mac in $_mac_list
    do
        name_dev="${section_name}_block_${_src_mac//:/}"

        echo "block device mac: $_src_mac, dev comment: $name_dev."

        share_access_remove $_src_mac

        iptables -t filter -A $share_block_table_input -m mac --mac-source $_src_mac -j DROP >/dev/null
        iptables -t filter -A $share_block_table -m mac --mac-source $_src_mac -j DROP >/dev/null
    done

    return;
}

share_block_apply()
{
    iptables -t filter -F $share_block_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT

    config_load ${section_name}

    config_foreach share_block_add_perdevice block
}

share_block_remove_all()
{
    iptables -t filter -F $share_block_table >/dev/null 2>&1
}

################### interface ###################
#sns : string, 社交网络代码
#guest_user_id : string, 好友id
#extra_payload : string
#mac : 放行设备mac地址
share_access_prepare()
{
    local _src_mac=$1
    local _device_id=""
    local _current=""
    local _start=""
    local _stop=""

    [ "$_src_mac" == "" ] && return 1;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    _device_id=${_src_mac//:/};
    _current=$(date  "+%Y-%m-%dT%H:%M:%S")
    _start=$(echo $_current | awk -v timeout=30 '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now-timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')
    _stop=$(echo $_current | awk -v timeout=$auth_timeout '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now+timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')

    local allowed_datestop=$(uci get ${section_name}.${_device_id}.datestop)
    [ "$allowed_datestop" != "" ] && {
        local time_now=$(echo $_current | tr -cd '[0-9]')
        local time_stop=$(echo $allowed_datestop | tr -cd '[0-9]')
        [ $time_stop -ge $time_now ]&& {
            return;
        }
    }

    local name_dev="${section_name}_${_device_id}"

    share_aceess_remove_iptables $_src_mac

    local dnsd_ok="0"
    ps | grep dnsd | grep -v grep >/dev/null 2>&1
    [ $? == 0 ] && {
        dnsd_ok="1"
    }

    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP
    if [ "$dnsd_ok" == 1 ];
    then
        iptables -t nat -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ${share_nat_dev_redirect_table}
    else
        iptables -t nat -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT
    fi

    return
}

share_access_allow()
{
    local _src_mac=$1
    local dev_sns=$2
    local _device_id=""
    local _start=""
    local _stop=""
    local force_write=0
    local online_time=$(ubus call trafficd hw |jason.sh -b |grep "$_mac"|grep online_timer |awk '{print $2}')
    [ "$_src_mac" == "" ] && return 1;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    _device_id=${_src_mac//:/};
    _current=$(date  "+%Y-%m-%dT%H:%M:%S")
    _start=$(date  "+%Y-%m-%dT%H:%M:%S")
    _stop=$(echo $_start | awk -v timeout=$timeout '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now+timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')

    local allowed_datestop=$(uci get ${section_name}.${_device_id}.datestop)
    local _payload=$(uci get ${section_name}.${_device_id}.extra_payload)

    force_write=$(is_active_type "$_type" "$active_type")
    #logger -p warn -t wifishare "force_write $force_write $dev_sns active $active_type"
    [ "$allowed_datestop" != "" -a "$force_write" == "0" ] && {
        local time_now=$(echo $_current | tr -cd '[0-9]')
        local time_stop=$(echo $allowed_datestop | tr -cd '[0-9]')
        [ $time_stop -ge $time_now ]&& {
            return;
        }
    }

    share_aceess_remove_iptables $_src_mac

    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP
    exe_ret1=$?
    iptables -t nat    -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT
    exe_ret2=$?

    [ "$exe_ret1" != "0" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|iptables_add1|$date_tag|$exe_ret1"
    [ "$exe_ret2" != "0" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|iptables_add2|$date_tag|$exe_ret2"

uci -q batch <<-EOF >/dev/null
    set ${section_name}.${_device_id}=device
    set ${section_name}.${_device_id}.datestart="$_start"
    set ${section_name}.${_device_id}.datestop="$_stop"
    set ${section_name}.${_device_id}.mac="$_src_mac"
    set ${section_name}.${_device_id}.timecount_last="$online_time"
EOF
    uci commit ${section_name}

    old_ticket=$(echo $_payload | jason.sh -b |grep "\[\"initial_ticket\"\]" |awk '{print $2}' |sed 's/\"//g')
    [ "$old_ticket" != "" ] && logger -p info -t wifishare "stat_points_none wifishare_allow=$_src_mac|$old_ticket|$date_tag"
    [ "$old_ticket" == "" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|nooldticket|$date_tag"
}

share_aceess_remove_iptables()
{
    local _src_mac=$1
    local _device_id=""

    [ "$_src_mac" == "" ] && return 1;

    _device_id=${_src_mac//:/};

#    iptables -t filter -A $share_filter_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -m comment --comment ${name_dev} -j DROP
iptables-save -t filter | awk -v mac=$_src_mac '/^-A wifishare_filter_device /  {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            if($(i+1)==mac)
            {
                gsub("^-A", "-D")
                print "iptables -t filter "$0";"
            }
        }
        i++
    }
}' |sh

iptables-save -t nat | awk -v mac=$_src_mac  '/^-A wifishare_nat_device / {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            if($(i+1)==mac)
            {
                gsub("^-A", "-D")
                print "iptables -t nat "$0";"
            }
        }
        i++
    }
}' |sh

   return;
}

share_access_remove()
{
    local _src_mac=$1

    share_aceess_remove_iptables $_src_mac

    share_contrack_remove $_src_mac

    logger -p info -t wifishare "stat_points_none wifishare_remove=$_src_mac|$date_tag"
    return
}

timeout_devname_list=""
timeout_time=""
share_timeout_gettime()
{
   timeout_time=$(echo 1|   awk '{now=systime(); print now }')
}

share_access_timeout_iptables()
{

   local _timeout_range=$1

   [ -z $_timeout_range ] && _timeout_range=$timeout
   [ "$_timeout_range" -le 3600 ] && _timeout_range=3600

   let _timeout_range+=30

iptables-save -t nat | awk -v  now=$timeout_time -v auth_timeout=$auth_timeout -v range=$_timeout_range '/^-A wifishare_nat_device / {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            need_remove=0;
            mac=$(i+1);
            device_id=mac;
            gsub(":", "", device_id);
        }

        if($i~/--datestart/)
        {
            datestart=$(i+1)
            gsub(/-|:|T/," ", datestart);
            start=mktime(datestart);
        }

        if($i~/--datestop/)
        {
            datestop=$(i+1);
            filter_datestart=datestop;
            gsub(/-|:|T/," ", datestop);
            stop=mktime(datestop);
            if(now>stop)
            {
                need_remove=1;
            }
            else if (now-start>range)
            {
                need_remove=1;
            }

        }

        if($i~/-j/)
        {
            if(need_remove == 1)
            {
                gsub("^-A", "-D");
                print "iptables -t filter -D wifishare_filter_device -m mac --mac-source "mac" -m time --datestart "filter_datestart" --kerneltz -j DROP";
                print "iptables -t nat "$0;
                print "logger -p info -t wifishare \"stat_points_none wifishare_timeout="mac"|"datestop"|"now"\""
            }
        }

        i++
    }
} '  |sh

   return
}

share_access_timeout_config_perdevice()
{
    local _mac=""
    local _datestop=""
    local _stop=""
    local _start=""

    local need_remove=0

    config_get _mac $section mac &>/dev/null;
    config_get _datestop $section datestop &>/dev/null;
    config_get _datestart $section datestart &>/dev/null;

    _stop=$(echo $_datestop |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')
    _start=$(echo $_datestart |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')

    [ "$timeout_range" != "" ] && {
        local _start_timeout
        let _start_timeout=$timeout_time-$_start

        echo $_start_timeout
        [  $_start_timeout -gt $timeout_range ] && {
            need_remove=1
        }
    }

    [ $_stop -lt $timeout_time ] && {
        need_remove=1;
    }

    [ "$need_remove" == "1" ] && {
        macsets_timeout="$macsets_timeout $_mac"
    }
}

share_access_timeout_uci()
{
    local macsets_timeout=""
    timeout_range=$1

    local onemac=""
    config_load "${section_name}"

    [ -z $timeout_range ] && timeout_range=$timeout
    [ "$timeout_range" -le 3600 ] && timeout_range=3600

    config_foreach share_access_timeout_config_perdevice device

    [ "$macsets_timeout" != "" ] && {
        for onemac in $macsets_timeout
        do
           local _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}



share_access_timeout()
{
    #get current time
    share_timeout_gettime

    #remove iptables
    share_access_timeout_iptables $1

    share_access_timeout_uci $1
    return
}

share_access_counting_perdevice()
{
    local dev_sns=""
    local _payload=""
    local _timecount=0
    local newcount=0
    local _mac=""
    local _datestop=""
    local _stop=""
    local _start=""
    local old_ticket=""
    local need_remove=0
    local _device_id=""

    config_get dev_sns $section sns &>/dev/null;
    [ "$dev_sns" != "$WIFIRENT_NAME" ] && return;

    config_get _mac $section mac &>/dev/null;
    [ "$_mac" == "" ] && {
        logger -p info -t wifishare "stat_points_none wifishare_error=$_mac|macempty"
        return;
    };

    _device_id=${_mac//:/};

    online_ifname=$(ubus call trafficd hw |jason.sh -b|grep "\[\"${_mac}\",\"ifname\"\]"|awk '{print $2}'| sed 's/\"//g')
    [ "$online_ifname" != "$guest_ifname" -o  "$online_ifname" == "" ] && {
        uci delete wifishare.${_device_id}.timecount_last
        logger -p info -t wifishare "stat_points_none wifishare_error=$_mac|onlineifnameempty"
        return;
    }

    config_get old_ticket $section ticket &>/dev/null;
    #[ "$_ticket" == "" ] && return;

    config_get _payload $section extra_payload &>/dev/null;
    [ "$_payload" == "" ] && {
        logger -p info -t wifishare "stat_points_none wifishare_error=$_mac|payloadempty"
        return;
    }

    config_get _lastcount $section timecount_last &>/dev/null;
    [ "$_lastcount" == "" ] && _lastcount=0;

    #config_get _datestop $section datestop &>/dev/null;
    #config_get _datestart $section datestart &>/dev/null;
    #_stop=$(echo $_datestop |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')
    #_start=$(echo $_datestart |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')
    online_time=$(ubus call trafficd hw |jason.sh -b |grep "$_mac"|grep wifishare_timer |awk '{print $2}')
    [ "$online_time" == "" ] && {
        uci delete wifishare.${_device_id}.timecount_last
        logger -p info -t wifishare "stat_points_none wifishare_error=$_mac|onlinetimeempty"
        return;
    }

    [ "$old_ticket" == "" ] && old_ticket=$(echo $_payload | jason.sh -b |grep "\[\"initial_ticket\"\]" |awk '{print $2}' |sed 's/\"//g')
    [ "$old_ticket" == "" ] && {
        logger -p info -t wifishare "stat_points_none wifishare_error=$_mac|oldticketempty"
        return;
    }

    if [ $_lastcount -eq 0 ]
    then
        newcount=60
    elif [ $_lastcount -ge $online_time ]
    then
        newcount=$COUNT_INTERVAL_SECS
    else
        newcount=$(expr $online_time - $_lastcount)
    fi

    wifishare_log "COUNTING $newcount seconds";
    #uci get wifishare.FC64BA9687F9.extra_payload | jason.sh -b
    #matool --method api_call --params /device/wifi_rent/counting "{\"ticket\":\"xxxx\",\"duration\":15}"
    report_success=0
    for report_try in `seq 1 3`
    do
        matool --method api_call --params /device/wifi_rent/counting "{\"ticket\":\"$old_ticket\", \"duration\":$newcount }" >$MATOOL_DATA_FILE

        _code=$( cat $MATOOL_DATA_FILE|jason.sh -b | grep "\"code\"" | awk '{print $2}')

        new_ticket=$(cat $MATOOL_DATA_FILE |jason.sh -b |grep "\[\"data\",\"ticket\"\]" | awk '{print $2}' |sed 's/\"//g')

        case $_code in
        4502 | 4503 )
            need_remove=1;
            echo "$date_tag $_mac $newcount $old_ticket $new_ticket $_code $need_remove remove" >> $COUNTING_DATA_FILE
            #logger -p info -t wifishare "stat_points_none wifishare_counting=$date_tag|$_mac|$newcount|$old_ticket|$new_ticket|$_code|$need_remove|remove"
            macsets_arrearage="$macsets_arrearage $_mac"
            report_success=1;
            break;
        ;;
        -1 )
            echo "$date_tag $_mac $newcount $old_ticket $new_ticket $_code $need_remove error" >> $COUNTING_DATA_FILE
            logger -p info -t wifishare "stat_points_none wifishare_counting=$date_tag|$_mac|$newcount|$old_ticket|$new_ticket|$_code|$need_remove|error"
            continue;
        ;;
        esac

        report_success=1;
        break
    done

    [ "$report_success" == "0" ] && {
        logger -p info -t wifishare "stat_points_none wifishare_counting=$date_tag|$_mac|$newcount|$old_ticket|$new_ticket|$_code|$need_remove|finalerror"
        return;
    }

    echo "$date_tag $_mac $newcount $old_ticket $new_ticket $_code $need_remove" >> $COUNTING_DATA_FILE
    #logger -p info -t wifishare "stat_points_none wifishare_counting=$_mac|$date_tag|$newcount|$old_ticket|$new_ticket|$_code|$need_remove|notremove"

    #echo "TIME: $date_tag"
    #echo "MAC $_mac"
    #echo "SECONDS $newcount"
    #echo "OLD TICKET $old_ticket"
    #echo "NEW TICKET $new_ticket"
    #echo "RETURN CODE $_code"
    #echo "NEED REMOVE $need_remove"
    #matool --method api_call --params /device/wifi_rent/counting "{\"ticket\":\"$_ticket\", \"duration\":1000}"
    #uci get wifishare.FC64BA9687F9.extra_payload | jason.sh -b |grep "\[\"sns\"\]" |awk '{print $2}'
    [ "$new_ticket" == "" ] && {
        return;
    }

    uci set wifishare.${_device_id}.timecount_last=${online_time}
    uci set wifishare.${_device_id}.ticket=${new_ticket}
    return;
}

share_access_counting()
{
    local macsets_arrearage=""
    timeout_range=$1

    local onemac=""
    config_load "${section_name}"

    config_foreach share_access_counting_perdevice device

    [ "$macsets_arrearage" != "" ] && {
        for onemac in $macsets_arrearage
        do
           local _device_id=""
            _device_id=${onemac//:/}
            share_access_remove ${onemac}
            #share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
    }

    uci commit ${section_name}
}

# add timer task to crontab
# eg.
# bridgeap mode gateway check
# */1 * * * * /usr/sbin/ap_mode.sh check_gw
#share_counting_stop_crontab()
#{
#   grep -v "/usr/sbin/wifishare.sh counting" /etc/crontabs/root > /etc/crontabs/root.new;
#   mv /etc/crontabs/root.new /etc/crontabs/root
#   /etc/init.d/cron restart
#}

#share_counting_start_crontab()
#{
#   grep -v "/usr/sbin/wifishare.sh counting" /etc/crontabs/root > /etc/crontabs/root.new;
#   echo "*/$COUNT_INTERVAL * * * * /usr/sbin/wifishare.sh counting" >> /etc/crontabs/root.new
#   mv /etc/crontabs/root.new /etc/crontabs/root
#   /etc/init.d/cron restart
#}

share_clean_config_perdevice_wifirent()
{
    local _mac=""
    #local _sns=""

    config_get _mac $section mac &>/dev/null;

    macsets_cleaned="$macsets_cleaned $_mac"
}


share_clean_wifirent()
{	
    local macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice_wifirent device

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           local _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}


share_clean_config_perdevice()
{
    local _mac=""
    local dev_sns=""

    config_get _mac $section mac &>/dev/null;
    config_get dev_sns $section sns &>/dev/null;
    [ "$dev_sns" == "$WIFIRENT_NAME" ] && return;

    macsets_cleaned="$macsets_cleaned $_mac"
}


share_clean_uci_device()
{
    local macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice device

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           local _device_id=""
            _device_id=${onemac//:/}
            #share_contrack_remove ${onemac}
            share_access_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}

share_clean_uci_record()
{
    local macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice record

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           local _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}"_RECORD"
        done
        uci commit ${section_name}
    }
}

share_clean_uci_block()
{
    uci delete ${section_name}.blacklist
    uci commit ${section_name}
}

share_clean()
{
    #iptables -t nat -F $share_nat_device_table >/dev/null 2>&1
    #iptables -t nat -F $share_nat_dev_redirect_table >/dev/null 2>&1
    #iptables -t filter -F $share_filter_device_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT

    share_clean_uci_device

    share_clean_uci_record

    share_clean_uci_block

    return;
}


share_reload()
{
    share_fw_remove_all

    share_ipset_create $share_whitehost_ipset

    [ "$_active" == "business" ] && business_init

    [ "$_active" == "business" ] || share_dnsd_start

    share_fw_add_default

    share_fw_add_device_all

    share_block_remove_default

    share_block_add_default

    [ "$_active" != "business" ] && share_block_apply
    return
}

share_config_set()
{
    local _auth_timeout=${1}
    local _timeout=${2}
    local _dhcp_leasetime=${3}

    [ ! -z $_dhcp_leasetime ] && {
uci -q batch <<-EOF >/dev/null
    set dhcp.guest.leasetime=${_dhcp_leasetime}
EOF
    uci commit dhcp
    /etc/init.d/dnsmasq restart
}

uci -q batch <<-EOF >/dev/null
    set firewall.${section_name}=include
    set firewall.${section_name}.path="/usr/sbin/wifishare.sh reload"
    set firewall.${section_name}.reload=1
    set ${section_name}.global.auth_timeout=${_auth_timeout}
    set ${section_name}.global.timeout=${_timeout}
EOF

    uci commit firewall
    uci commit ${section_name}

    return;
}

share_config_set_default()
{
uci -q batch <<-EOF >/dev/null
    del firewall.${section_name}
    set ${section_name}.global.auth_timeout=${auth_timeout_default}
    set ${section_name}.global.timeout=${timeout_default}
    set dhcp.guest.leasetime=12h
EOF

    uci commit ${section_name}
    uci commit dhcp
    uci commit firewall

    /etc/init.d/dnsmasq restart

}

share_start()
{

    local name_default="${section_name}_default"
    local _auth_timeout=${1}
    local _timeout=${2}
    local _dhcp_leasetime=${3}

    has_wifishare=$(uci get firewall.wifishare.path)

    [ "$has_wifishare" == "/usr/sbin/wifishare.sh reload" ]  && return

    [ -z $_auth_timeout ] && _auth_timeout=${auth_timeout_default}
    [ -z $_timeout ] && _timeout=${timeout_default}

    share_reload

    share_config_set $@

    return
}

share_stop()
{
    share_config_set_default

    share_contrack_remove_all

    share_fw_remove_all

    share_block_remove_all

    share_block_remove_default

    share_ipset_destroy $share_whitehost_ipset

    share_dnsd_stop

    share_clean

    return
}

guest_network_judge()
{
    local _encryption=$(uci get wireless.guest_2G.encryption 2>/dev/null)
    local _ssid=$(uci get wireless.guest_2G.ssid 2>/dev/null)
    local _disabled=$(uci get wireless.guest_2G.disabled 2>/dev/null)

    [ "$_disabled" == 1 ] && exit 1
    [ "$_ssid" == "" ] && exit 1
    [ "$_encryption" != "none" ] && exit 1

    return
}

share_usage()
{
    echo "$0:"
    echo "    on     : start guest share, guest must open and encryption is none."
    echo "        format: $0 on auth_timeout timeout"
    echo "                auth_timeout default 60 seconds(one minute). "
    echo "                timeout default 86400 second(one day)"
    echo "                dhcp_leasetime default 12h (12 hour). other example 60m"
    echo "        eg: $0 on"
    echo "        eg: $0 on 120 7200 2h"
    echo "    off    : stop guest share."
    echo "        format: $0 off"
    echo "    block_apply: apply block list."
    echo "        format: $0 block_apply"
    echo "    prepare: prepare for guest client, allow data transfer for 60 seconds."
    echo "        format: $0 prepare mac_address"
    echo "        eg    : $0 prepare 01:12:34:ab:cd:ef"
    echo "    allow  : access allow, default 1 day."
    echo "        format: $0 allow mac_address"
    echo "        eg    : $0 allow 01:12:34:ab:cd:ef"
    echo "    deny   : access deny, default 1 day."
    echo "        format: $0 deny mac_address"
    echo "        eg    : $0 deny 01:12:34:ab:cd:ef"
    echo "    timeout: remove timeout item in firewall iptables wifishare."
    echo "        format: $0 timeout"
    echo "    other: usage."

    return;
}

daemon_stop()
{
    local this_pid=$$
    local one_pid=""
    local _pid_list=""
    echo $$ >$counting_pid

    ps w|grep wifishare_daemon.sh|grep -v grep

    _pid_list=$(ps w|grep wifishare_daemon.sh|grep -v grep |grep -v counting|awk '{print $1}')
    for one_pid in $_pid_list
    do
        echo "curent try pid "$one_pid" end"
        [ "$one_pid" != "$this_pid" ] && {
            echo "wifishare kill "$one_pid
            kill -9 $one_pid
        }
    done
    echo "wifishare daemon stop"
}

daemon_start()
{
    daemon_stop
    $daemonfile daemon &
}

daemon_run()
{
    sleep 60
    while true
    do
        $daemonfile counting
        sleep $COUNT_INTERVAL_SECS
    done
}

OPT=$1

config_load "${section_name}"

config_foreach share_parse_global global

config_foreach share_parse_block block
#main
wifishare_log "$OPT"

case $OPT in
    on)
        
        guest_network_judge

        hwnat_stop

        fw3_lock
        share_start $2 $3 $4
        fw3_unlock

        daemon_start
        #share_counting_start_crontab
        return $?
    ;;

    off)
        #share_counting_stop_crontab
        fw3_lock
        share_stop
        fw3_unlock

        hwnat_start

        daemon_stop
        return $?
    ;;

    prepare)
        local _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        fw3_lock
        wifishare_log "$OPT begin"
        share_access_prepare $_dev_mac
        #share_access_timeout

        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    allow)
        local _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        local _dev_sns="$3"
        fw3_lock
        wifishare_log "$OPT begin"
        share_access_allow $_dev_mac $_dev_sns
        share_access_timeout
        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    deny)
        #deny issue don't delete uci config
        local _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        fw3_trylock
        wifishare_log "$OPT begin"
        [ "$_locked" == "1" ] && return;
        share_access_remove $_dev_mac
        share_access_timeout
        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    block_apply)
        fw3_trylock
        [ "$_locked" == "1" ] && return;
        share_block_apply
        fw3_unlock
        return $?
    ;;

    counting)
        fw3_trylock
        [ "$_locked" == "1" ] && return;
        wifishare_log "$OPT begin"
        share_access_counting
        wifishare_log "$OPT end"
        fw3_unlock
    ;;

    daemon)
        daemon_run
    ;;

    timeout)
        local _timeout=$(echo $2 | sed 's/[^0-9]//g')
        fw3_trylock
        share_access_timeout $_timeout
        fw3_unlock
        return $?
    ;;

    clean)
        fw3_trylock
        [ "$_locked" == "1" ] && return;
        wifishare_log "$OPT begin"
        share_clean
        #share_clean_wifirent
        wifishare_log "$OPT end"
        fw3_unlock
        logger -p info -t wifishare "stat_points_none wifishare_clean=$date_tag"
    ;;

    reload)
        wifishare_log "$OPT begin"
        share_reload
        daemon_start
        wifishare_log "$OPT end"
        return $?
    ;;

    *)
        share_usage
        return 0
    ;;
esac


