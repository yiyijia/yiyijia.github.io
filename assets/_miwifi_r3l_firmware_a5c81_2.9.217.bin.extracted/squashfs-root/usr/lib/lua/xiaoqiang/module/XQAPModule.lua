module ("xiaoqiang.module.XQAPModule", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local LuciUtil = require("luci.util")
local UCI = require("luci.model.uci").cursor()
local HARDWARE = UCI:get("misc", "hardware", "model") or ""
local logger = require("xiaoqiang.XQLog")
if HARDWARE then
    HARDWARE = string.lower(HARDWARE)
end

function setLanAPMode()
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local messagebox = require("xiaoqiang.module.XQMessageBox")
    local apmode = XQFunction.getNetMode() ~= nil
    local olanip = XQLanWanUtil.getLanIp()
    if not apmode then
        local uci = require("luci.model.uci").cursor()
        local lan = uci:get_all("network", "lan")
        uci:section("backup", "backup", "lan", lan)
        uci:commit("backup")
    end
    os.execute("/usr/sbin/ap_mode.sh connect >/dev/null 2>/dev/null")
    local nlanip = XQLanWanUtil.getLanIp()
    if olanip ~= nlanip then
        local XQSync = require("xiaoqiang.util.XQSynchrodata")
        messagebox.removeMessage(4)
        XQWifiUtil.setWiFiMacfilterModel(false)
        XQWifiUtil.setGuestWifi(1, nil, nil, nil, 0, nil)
        XQFunction.setNetMode("lanapmode")
        XQSync.syncApLanIp(nlanip)
        return nlanip
    end
    return nil
end

function disableLanAP()
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local uci = require("luci.model.uci").cursor()
    local lanip = uci:get("backup", "lan", "ipaddr")
    XQFunction.setNetMode(nil)
    return lanip
end

function lanApServiceRestart(open, fork)
    local cmd1 = [[
        sleep 7;
        /usr/sbin/ap_mode.sh open;
        /usr/sbin/shareUpdate -b >/dev/null 2>/dev/null;
    ]]
    local cmd2 = [[
        sleep 5;
        /usr/sbin/ap_mode.sh close;
        /usr/sbin/shareUpdate -b >/dev/null 2>/dev/null;
    ]]
    if fork then
        if open then
            XQFunction.forkExec(cmd1)
        else
            XQFunction.forkExec(cmd2)
        end
    else
        if open then
            os.execute(cmd1)
        else
            os.execute(cmd2)
        end
    end
end

function backupConfigs()
    local uci = require("luci.model.uci").cursor()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local xqsys = require("xiaoqiang.util.XQSysUtil")

    local lan = uci:get_all("network", "lan")
    local dhcplan = uci:get_all("dhcp", "lan")
    local dhcpwan = uci:get_all("dhcp", "wan")

    uci:delete("backup", "lan")
    uci:delete("backup", "wifi1")
    uci:delete("backup", "wifi2")
    uci:delete("backup", "dhcplan")
    uci:delete("backup", "dhcpwan")

    uci:section("backup", "backup", "lan", lan)
    uci:section("backup", "backup", "dhcplan", dhcplan)
    uci:section("backup", "backup", "dhcpwan", dhcpwan)
    uci:commit("backup")

    if xqsys.getInitInfo() then
        wifi.backupWifiInfo(1)
        wifi.backupWifiInfo(2)
    end
end

function setWanAuto(auto)
    local LuciNetwork = require("luci.model.network").init()
    local wan = LuciNetwork:get_network("wan")
    wan:set("auto", auto)
    LuciNetwork:commit("network")
end

function disableWifiAPMode(ifname)
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local uci = require("luci.model.uci").cursor()

    local lan = uci:get_all("backup", "lan")
    local dhcplan = uci:get_all("backup", "dhcplan")
    local dhcpwan = uci:get_all("backup", "dhcpwan")

    local lanip, ssid
    uci:delete("network", "lan")
    if lan then
        uci:section("network", "interface", "lan", lan)
        lanip = lan.ipaddr
    else
        uci:section("network", "interface", "lan", NETWORK_LAN)
        lanip = NETWORK_LAN.ipaddr
    end
    if dhcplan then
        uci:section("dhcp", "dhcp", "lan", dhcplan)
    end
    if dhcpwan then
        uci:section("dhcp", "dhcp", "wan", dhcpwan)
    end
    uci:commit("dhcp")
    uci:commit("network")

    setWanAuto(nil)

    wifi.apcli_disable(ifname)
    XQFunction.setNetMode(nil)
    wifi.apcli_set_active(nil)
    local restore_script = [[
        sleep 3;
        /etc/init.d/network restart;
        /etc/init.d/dnsmasq restart;
        /usr/sbin/dhcp_apclient.sh restart lan;
        /etc/init.d/trafficd restart;
        /usr/sbin/shareUpdate -b;
        /etc/init.d/xqbc restart
    ]]
    if not ssid then
        ssid = wifi.getWifissid()
    end
    XQFunction.forkExec(restore_script)
    return lanip, ssid
end

function serviceRestart(fast)
    local restart_script
    if fast then
        restart_script = [[
            /etc/init.d/network restart;
            /etc/init.d/trafficd restart;
            /usr/sbin/shareUpdate -b;
            /etc/init.d/dnsmasq restart;
            /usr/sbin/dhcp_apclient.sh restart lan;
            /etc/init.d/xqbc restart;
            /etc/init.d/miqos stop
        ]]
    else
        restart_script = [[
            sleep 10;
            /etc/init.d/network restart;
            /etc/init.d/trafficd restart;
            /usr/sbin/shareUpdate -b;
            /etc/init.d/dnsmasq restart;
            /usr/sbin/dhcp_apclient.sh restart lan;
            /etc/init.d/xqbc restart;
            /etc/init.d/miqos stop
        ]]
    end
    XQFunction.forkExec(restart_script)
end

function parseCmdline(str)
    if XQFunction.isStrNil(str) then
        return ""
    else
        return str:gsub("\\", "\\\\"):gsub("`", "\\`"):gsub("\"", "\\\""):gsub("%$", "\\$")
    end
end

function setWifiAPMode(ssid, password, enctype, encryption, band, channel, bandwidth, nssid, nencryption, npassword, nssid5G)
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local apcliitem = {
          ["ifname"] = "",
          ["ssid"] = ssid,
          ["cmdssid"] = ssid,
          ["password"] = password,
          ["cmdpassword"] = password,
          ["encryption"] = encryption,
          ["enctype"] = enctype,
          ["band"] = band,
          ["channel"] = channel,
          ["bw"] = bandwidth
    }

    local result = {
        ["connected"]   = false,
        ["conerrmsg"]   = "",
        ["scan"]        = true,
        ["ip"]          = ""
    }
    local ifname
    local apmode = XQFunction.getNetMode() ~= nil

    if apcliitem.ssid then
        apcliitem.cmdssid = parseCmdline(apcliitem.ssid)
        apcliitem.cmdpassword = parseCmdline(apcliitem.password)

--没有指定的情况下才扫描
	if XQWifiUtil.apcli_check_apcliitem(apcliitem) then
            local scanlist = XQWifiUtil.apcli_get_scanlist(apcliitem)
            local wifi
            for _, item in ipairs(scanlist) do
                if item and item.ssid == ssid then
                    wifi = item
                    break
                end
            end
            if not wifi then
                result["scan"] = false
                return result
            end
            apcliitem.enctype = wifi.enctype
            apcliitem.channel = wifi.channel
            apcliitem.encryption = wifi.encryption
            apcliitem.band = wifi.band
            apcliitem.channel = wifi.channel
            apcliitem.ifname = wifi.ifname
        end

        if XQFunction.isStrNil(apcliitem.ifname) then
            apcliitem.ifname = XQWifiUtil.apcli_get_ifname_form_band(apcliitem.band)
        end

--防止环路
        local ifnames = XQWifiUtil.apcli_get_ifnames()
        local ifname_other
        for _, ifname_other in ipairs(ifnames) do
            if ifname_other ~= apcliitem.ifname then
                XQWifiUtil.apcli_set_inactive(ifname_other)
            end
        end

--enable new apcli
        XQWifiUtil.apcli_set_connect(apcliitem) 

        local connected = false
        for i=1, 10 do
            local succ, status = XQWifiUtil.apcli_get_connect(apcliitem.ifname)
            if succ then
                connected = true
                break
            end
            os.execute("sleep 2")
        end
        result["connected"] = connected
    end

    if result.connected then
        local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
        if not apmode then
            backupConfigs()
        end
        local uci = require("luci.model.uci").cursor()
        local oldlan = uci:get_all("network", "lan")
        setWanAuto(0)

        -- get ip
        local dhcpcode = tonumber(os.execute("sleep 2;dhcp_apclient.sh start "..apcliitem.ifname))
        if dhcpcode ~= 0 then
            dhcpcode = tonumber(os.execute("sleep 2;dhcp_apclient.sh start br-lan"))
        end

        local newip = XQLanWanUtil.getLanIp()
        if dhcpcode and dhcpcode == 0 then
            local XQSync = require("xiaoqiang.util.XQSynchrodata")
            XQFunction.setNetMode("wifiapmode")
            XQSync.syncApLanIp(newip)
            result["ip"] = newip
            local uci = require("luci.model.uci").cursor()
            uci:delete("dhcp", "lan")
            uci:delete("dhcp", "wan")
            uci:commit("dhcp")

            local wifissid, wifi5gssid, wifipawd, wifienc
            if not XQFunction.isStrNil(nssid) and nencryption and (npassword or nencryption == "none") then
                wifissid = nssid
                wifi5gssid = nssid
                wifipawd = npassword
                wifienc = nencryption
            end
            if not XQFunction.isStrNil(nssid5G) then
                wifi5gssid = nssid5G
            end
            XQWifiUtil.setWifiBasicInfo(1, wifissid, wifipawd, wifienc, nil, nil, nil, nil, nil, nil)
            XQWifiUtil.setWifiBasicInfo(2, wifi5gssid, wifipawd, wifienc, nil, nil, nil, nil, nil, nil)
--enable apcli
            XQWifiUtil.apcli_enable(apcliitem)
            XQWifiUtil.setWiFiMacfilterModel(false)
            XQWifiUtil.setGuestWifi(1, nil, nil, nil, 0, nil)
            if XQFunction.isStrNil(wifissid) then
                local info = XQWifiUtil.getWifiBasicInfo(1)
                if info ~= nil then
                    result["ssid"] = info.ssid
                end
            else
                result["ssid"] = wifissid
            end
            if XQFunction.isStrNil(wifi5gssid) then
                local info = XQWifiUtil.getWifiBasicInfo(2)
                if info ~= nil then
                    result["ssid5G"] = info.ssid
                end
            else
                result["ssid5G"] = wifi5gssid
            end
        else
            setWanAuto(nil)
--resurve old lan ip
            local uci = require("luci.model.uci").cursor()
            uci:delete("network", "lan")
            uci:section("network", "interface", "lan", oldlan)
            uci:commit("network")
        end
    end

--
    if not result.connected or result.ip == "" then
        local ifnames = XQWifiUtil.apcli_get_ifnames()
        local ifname_other
        for _, ifname_other in ipairs(ifnames) do
               XQWifiUtil.apcli_set_inactive(ifname_other)
        end
 --enable
        if apmode then
            local old_active = XQWifiUtil.apcli_get_active()
            local old_wifinet = XQWifiUtil.apcli_get_wifinet(old_active)
            local old_apcliitem = {
                  ["ifname"] = old_active,
                  ["ssid"] = old_wifinet:get('ssid'),
                  ["password"] = old_wifinet:get('key') or "",
                  ["encryption"] = old_wifinet:get('encryption') or "",
                  ["enctype"] = old_wifinet:get('enctype') or ""
               }
            XQWifiUtil.apcli_set_connect(old_apcliitem)
        else
--channel bw
        end
        result['conerrmsg'] = "Connect faild!"
    end

    return result
end

function extednwifi_disconnect(band)
   local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")

   if XQFunction.isStrNil(band) then
       band = "2g"
   end

   ifname = XQWifiUtil.apcli_get_ifname_form_band(band)
   XQWifiUtil.apcli_set_inactive(ifname)
end

function extendwifi_set_connect(ssid, password, enctype, encryption, band, channel)
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local apcliitem = {
          ["ifname"] = "",
          ["ssid"] = ssid,
          ["cmdssid"] = ssid,
          ["password"] = password,
          ["cmdpassword"] = password,
          ["encryption"] = encryption,
          ["enctype"] = enctype,
          ["band"] = band,
          ["channel"] = channel,
    }

    local result = {
        ["connected"]   = false,
        ["dhcpcode"]    = -1,
        ["ip"]          = ""
    }
    local ifname

    local apmode = XQFunction.getNetMode() ~= nil

    if apcliitem.ssid then
        apcliitem.ssid = parseCmdline(apcliitem.ssid)
        apcliitem.password = parseCmdline(apcliitem.password)

--没有指定的情况下才扫描
        if XQWifiUtil.apcli_check_apcliitem(apcliitem) then
            local scanlist = XQWifiUtil.apcli_get_scanlist(apcliitem)
            local wifi
            for _, item in ipairs(scanlist) do
                if item and item.ssid == ssid then
                    wifi = item
                    break
                end
            end
            if not wifi then
                return result
            end
            apcliitem.enctype = wifi.enctype
            apcliitem.channel = wifi.channel
            apcliitem.encryption = wifi.encryption
            apcliitem.band = wifi.band
            apcliitem.channel = wifi.channel
            apcliitem.ifname = wifi.ifname
        end

        if XQFunction.isStrNil(apcliitem.ifname) then
            apcliitem.ifname = XQWifiUtil.apcli_get_ifname_form_band(apcliitem.band)
        end
--enable new apcli

--默认从桥上掉下来?
--        os.execute("brctl delif br-lan apcli0")

        XQWifiUtil.apcli_set_connect(apcliitem)

        local connected = false
        for i=1, 10 do
            local succ, status = XQWifiUtil.apcli_get_connect(apcliitem.ifname)
            if succ then
                connected = true
                break
            end
            os.execute("sleep 2")
        end
        result["connected"] = connected
    end

    if result.connected then
        local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
        local uci = require("luci.model.uci").cursor()
        local xqextendwifi = require("xiaoqiang.module.XQExtendWifi")
        -- get ip
        result.dhcpcode = tonumber(luci.util.exec("/usr/sbin/dhcpc_do_opt43_act.sh "..apcliitem.ifname.." 2> /dev/NULL >&2 ; echo $?") or "-1")

        if result.dhcpcode == 0 then
             result.ip = xqextendwifi.get_self_ip()
        end
    end

    if not result.connected or result.ip == "" then
        XQWifiUtil.apcli_set_inactive(apcliitem.ifname)
 --roll back
        if apmode then
            local old_active = XQWifiUtil.apcli_get_active()
            local old_wifinet = XQWifiUtil.apcli_get_wifinet(old_active)
            local old_apcliitem = {
                  ["ifname"] = old_active,
                  ["ssid"] = old_wifinet:get('ssid'),
                  ["password"] = old_wifinet:get('key') or "",
                  ["encryption"] = old_wifinet:get('encryption') or "",
                  ["enctype"] = old_wifinet:get('enctype') or ""
               }
            local disable = old_wifinet:get('disabled') or "0"
            if disable == "0" then
                XQWifiUtil.apcli_set_connect(old_apcliitem)
            end
        else
--channel bw
        end
    end

    return result
end
