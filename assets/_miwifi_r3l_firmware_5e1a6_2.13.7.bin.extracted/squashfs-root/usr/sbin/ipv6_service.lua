#!/usr/bin/lua
--[[
ipv6 turbo service deamon program
Author: MIWIFI@2017
--]]

--local uci = require 'luci.model.uci'
--local fs = require "nixio.fs"
local LuciUtil = require("luci.util")
local LuciJson = require("cjson")
local px = require "posix"
local math = require "math"
local service_name = 'ipv6'
local set_name = service_name
local proto_name = 'l2tp'

require "turbo.turbo_util"

local E_OK = 'OK';
local E_NOK = 'UNKNOWN';
local E_VIP = 'VIP';
local E_NON_VIP_OK = 'NON_VIP_OK';
local E_NON_VIP_NOK = 'NON_VIP_NOK';
g_debug = nil
g_debug = 1

-- init uloop
local uloop = require "uloop"
uloop.init()

-- init ubus
local ubus = require "ubus"
local conn = ubus.connect()
if not conn then
    logger("init ubus failed.")
    os.exit(-1)
end


IPV6_SERVICE = {
    uid = nil,
    passwd = nil,
    errorCode = 0,
    queryInfo = { companyID = nil, code = nil, userName = nil },
    vpn_server = nil,
    vpnInfo = {},
    usageInfo = {
        info = {},
        vip = E_NOK,
        vip_expire_days = 0,
        nonvip_left_count = 0,
    },

    --
    init = function()
        -- try to enable ipv6 service
        LuciUtil.exec("/etc/init.d/ipv6 on " .. service_name)

        IPV6_SERVICE.get_cid_code();

        -- DO NOT get passport at 1st startup, it may get wrong value.
        --IPV6_SERVICE.get_passport();

        --        -- check if it's ON
        --        local onFlag = read_cfg('turbo', service_name, 'flag', '0')
        --        if onFlag == '1' then
        --            IPV6_SERVICE.start_service()
        --        end
    end,

    -- update ipv6 related DNS or server Data
    update_ipv6_dns = function(dnsValue)
        if dnsValue then
            write_cfg('turbo', service_name, 'dns', dnsValue)
            LuciUtil.exec("echo " .. dnsValue .. " > /tmp/ip6_dns")

            -- download dns config whitelist
            IPV6_SERVICE.update_DNS_wlist(false)
        else
            write_cfg('turbo', service_name, 'dns', nil)
            LuciUtil.exec(" > /tmp/ip6_dns")
            IPV6_SERVICE.update_DNS_wlist(true)
        end

        -- kill send signal to dnsmasq to reload config
        -- LuciUtil.exec("ps |grep dnsmasq |grep -v grep|awk '{print $1}' |xargs kill -USR2")
        LuciUtil.exec("/etc/init.d/dnsmasq restart 2>/dev/null")
    end,

    -- check br-lan ipv6 fe80 ip
    check_lan_fe80_locallink = function()
        local res = trim(LuciUtil.exec('ifconfig br-lan |grep "inet6 addr: fe80:" 2>/dev/null'))
        if not res or res == '' then
            logerr("set br-lan ipv6 locallink addr for empty fe80 locallink.")
            set_dev_fe80_rand_addr('br-lan')
        end
    end,

    --
    start_service = function()
        logerr("turbo ipv6 starting...")
        if not IPV6_SERVICE.get_cid_code() then
            return -1, 'get cid failed.'
        end
        IPV6_SERVICE.check_lan_fe80_locallink()
        if not IPV6_SERVICE.get_passport() then
            return -2, 'get passport failed.'
        end

        if not IPV6_SERVICE.get_vip_info() then
            return -5, 'get usage info failed or free usage used-up or not VIP user.'
        end

        for i = 1, 3 do
            if IPV6_SERVICE.get_vpn_server() then
                break
            end
        end

        if not IPV6_SERVICE.vpn_server or IPV6_SERVICE.vpn_server == '' then
            return -3, 'get vpn server failed.'
        end

        if IPV6_SERVICE.uid and IPV6_SERVICE.passwd and IPV6_SERVICE.vpn_server and IPV6_SERVICE.vpn_server.server then
            print(service_name .. ',VPN=' .. IPV6_SERVICE.vpn_server.server .. ',UID=' .. IPV6_SERVICE.uid .. ',PASSWD=' .. IPV6_SERVICE.passwd)

            local data = {
                service = service_name,
                server = IPV6_SERVICE.vpn_server.server,
                username = IPV6_SERVICE.uid,
                password = IPV6_SERVICE.passwd,
                ipv6 = true,
                dns = IPV6_SERVICE.vpn_server.dns,
                peerdns = '0',
                peerdns6 = '0'
            }

            set_dev_fe80_rand_addr('br-lan')

            return 0, 'start in progress', data

        else
            logerr("ERROR: cannot start ipv6 vpn, uid=" .. (IPV6_SERVICE.uid or 'nil')
                    .. ', pass=' .. (IPV6_SERVICE.passwd or 'nil') .. ', server=' .. (IPV6_SERVICE.vpn_server or 'nil'))
            return -4, 'uid/passwd/vpn_server incorrect.'
        end
    end,

    --
    start_service_real = function(data)
        vpnOn(data)
    end,

    --
    stop_service = function()
        logerr("turbo ipv6 stopping...")
        vpnOff(service_name, false)
    end,

    --
    get_cid_code = function()
        IPV6_SERVICE.queryInfo.companyID = '1490838811997'
        IPV6_SERVICE.queryInfo.code = '354674s3f'
        return true
    end,

    --
    update_DNS_wlist = function(clean)

        if clean then
            LuciUtil.exec(" > /tmp/hosts/ip6_host")
            LuciUtil.exec(" > /tmp/ip6_server")
            return
        end

        local cmd = 'curl -s "http://api.miwifi.com/data/ipv6_dns_config" 2>/dev/null'
        local data = exec_cmd_s(cmd)
        local ret, out = pcall(function() return LuciJson.decode(data) end)
        if ret and out then
            local content_server = {}
            local content_host = {}

            for i = 1, #out do
                local onedns = out[i]
                local v_dns
                if onedns.dnsList and #onedns.dnsList >= 1 then
                    v_dns = onedns.dnsList[1]

                    if onedns.domainList then
                        local v_domainList = onedns.domainList;
                        for i = 1, #v_domainList do
                            local v_domain = v_domainList[i]
                            if v_domain and v_domain.domain then
                                if not v_domain.ipList or #v_domain.ipList <= 0 or trim(v_domain.ipList[1]) == '' then
                                    content_server[#content_server + 1] = 'server=/' .. v_domain.domain .. '/' .. v_dns .. '\n'
                                else
                                    -- domain goes to such DNS server, including A & AAAA
                                    content_server[#content_server + 1] = 'server=/' .. v_domain.domain .. '/' .. v_dns .. '\n'
                                    -- directly returned with hosts configured ip
                                    content_host[#content_host + 1] = v_domain.ipList[1] .. "    " .. v_domain.domain .. '\n'
                                end
                            end
                        end
                    end
                end
            end

            -- update ip6_server file
            if #content_server > 0 then
                local file = io.open("/tmp/ip6_server", "w")
                for i = 1, #content_server do
                    file:write(content_server[i])
                end
                file:close()
            end

            -- update ip6_host file
            if #content_host > 0 then
                local file = io.open("/tmp/hosts/ip6_host", "w")
                for i = 1, #content_host do
                    file:write(content_host[i])
                end
                file:close()
            end
        end
    end,

    --
    get_passport = function()
        if IPV6_SERVICE.uid and IPV6_SERVICE.passwd and
                IPV6_SERVICE.uid ~= '' and IPV6_SERVICE.passwd ~= '' then
            return true
        end
        local cmd = "matool --method api_call --params /device/radius/info 2>/dev/null"
        for i = 1, 2 do -- retry times
            local output = LuciUtil.trim(LuciUtil.exec(cmd))

            if output and output ~= "" then
                local ret, account = pcall(function() return LuciJson.decode(output) end)

                if ret and account and type(account) == "table" and
                        account.code == 0 and account.data then
                    IPV6_SERVICE.uid = account.data.name
                    IPV6_SERVICE.passwd = account.data.password
                    return true;
                end
            end
        end

        IPV6_SERVICE.uid = nil
        IPV6_SERVICE.passwd = nil
        return false
    end,

    -- read vpn server from cc periodly
    get_vpn_server = function()
        if not IPV6_SERVICE.uid or not IPV6_SERVICE.passwd then
            IPV6_SERVICE.get_passport()
        end

        -- get vpn server info from cc
        local para = IPV6_SERVICE.queryInfo
        para.data = {}
        para.uid = IPV6_SERVICE.uid
        para.data.passwd = IPV6_SERVICE.passwd
        para.time = os.time()

        local cmd = 'curl -s -d "companyId=1490838811997&code=354674s3f&deviceId=' .. IPV6_SERVICE.uid ..
                '" "http://slt.6luyou.com/ly_xm/getIpAddress" 2>/dev/null'
        local data = exec_cmd_s(cmd)
        local ret, out = pcall(function() return LuciJson.decode(data) end)

        if ret and out.state == '0' and out.server and out.dns then
            local sip = split(out.server, ':')
            IPV6_SERVICE.vpn_server = out
            IPV6_SERVICE.vpn_server.server = sip[1]
            IPV6_SERVICE.vpn_server.port = sip[2] or ''

            -- IPV6_SERVICE.vpn_server.server = '119.90.39.104'
            logger('connect to VPN server: ' .. IPV6_SERVICE.vpn_server.server)
            return true
        end
        return false
    end,

    --check if service can avaiable for such user
    get_vip_info = function()
        local param = { provider = 'sellon' }
        for i = 1, 2 do -- retry times
            local s = LuciUtil.exec("/usr/bin/matool --method api_call_post --params /device/vip/info/use '" .. LuciJson.encode(param) .. "'")
            local ret, result = pcall(function()
                return LuciJson.decode(LuciUtil.trim(s))
            end)

            if ret and result and result.code == 0 and result.data then
                IPV6_SERVICE.usageInfo.info = result.data
                -- check vip 1stly
                local t_vipInfo = result.data.vipInfo
                local curTs = os.time()
                if t_vipInfo then
                    local vipEndtime = t_vipInfo.endTime / 1000
                    if t_vipInfo.endTime > 0 then
                        if curTs < vipEndtime then
                            IPV6_SERVICE.usageInfo.vip = E_VIP;
                            IPV6_SERVICE.usageInfo.vip_expire_days = math.floor((vipEndtime - curTs) / 3600 / 24)
                            return true
                        end
                    end
                end

                -- check free trial
                if result.data.freeInfo then
                    local leftTime = tonumber(result.data.freeInfo.maxTime or 0) - (curTs - tonumber(result.data.freeInfo.lastActiveTime or 0))
                    if leftTime < 0 then
                        leftTime = 0
                    end

                    local leftCount = result.data.freeInfo.maxCount - result.data.freeInfo.countUsed
                    if leftCount < 0 then
                        leftCount = 0
                    end
                    IPV6_SERVICE.usageInfo.nonvip_left_count = leftCount
                    if leftCount > 0 or (leftCount == 0 and leftTime >= 0) then
                        IPV6_SERVICE.usageInfo.vip = E_NON_VIP_OK
                        return true
                    else
                        IPV6_SERVICE.usageInfo.vip = E_NON_VIP_NOK
                        IPV6_SERVICE.stop_service()
                        return true;
                    end
                else
                    -- if no freeinfo, will stop it
                    if IPV6_SERVICE.vpnStatus == 0 then
                        IPV6_SERVICE.stop_service()
                    end
                    return true;
                end
            end
        end

        IPV6_SERVICE.usageInfo.vip = E_NOK;
        return false
    end,

    -- download iplist for polic-routing
    apply_route_iplist = function()
        logger("fun: apply_route_iplist")
        local cmd = 'curl -s -d "companyId=1490838811997&code=354674s3f&deviceId=' .. IPV6_SERVICE.uid ..
                '" "http://slt.6luyou.com/ly_xm/getVpnAddress" 2>/dev/null'
        local data = exec_cmd_s(cmd)
        local ret, out = pcall(function() return LuciJson.decode(data) end)

        if (ret and out and out.state == "0" and out.vpnList)
        then
            logger("apply ips: " .. LuciJson.encode(out))
            route_add_ipnet(set_name, out.vpnList)            
        end
    end,

    clean_route_iplist = function()
        LuciUtil.exec('ipset flush ' .. set_name)
    end,

    -- get qos info for debugging
    get_ppplog = function()
        local output = LuciUtil.exec('cat /tmp/pppoe.log 2>/dev/null')
        return output
    end,

    --
    get_ifconfig = function()
        return LuciUtil.exec('ip a 2>/dev/null')
    end,

    --
    get_ip6_data = function()
        return LuciUtil.exec('echo =DNS===========; cat /tmp/ip6_dns;'
                .. 'echo =Host=========; cat /tmp/hosts/ip6_host;'
                .. 'echo =Server=========; cat /tmp/ip6_server;')
    end,
}


-- ubus call interface
local ipv6_method = {
    turbo_ipv6 =
    {
        start = {
            function(req)
                local ret = { code = 0, msg = 'ok' }
                local data

                -- check if already connected
                _, IPV6_SERVICE.vpnInfo = getVpnStatus(service_name, proto_name)
                if IPV6_SERVICE.vpnInfo and IPV6_SERVICE.vpnInfo.status == 1 then
                    ret.code = 0
                    ret.msg = 'already connected.'
                    conn:reply(req, ret)
                    return
                end

                ret.code, ret.msg, data = IPV6_SERVICE.start_service()
                conn:reply(req, ret)

                -- real work here.
                logger("turbo_ipv6 start: " .. ret.msg)
                if ret.code == 0 then
                    IPV6_SERVICE.start_service_real(data)
                end
            end, {}
        },

        --
        stop = {
            function(req)
                local ret = { code = 0, msg = 'ok' }
                conn:reply(req, ret)

                -- real work here.
                logger("turbo_ipv6 stop: " .. ret.msg)
                IPV6_SERVICE.stop_service()
            end, {}
        },

        --
        status = {
            function(req)
                local ret = { code = 0, msg = 'ok' }
                _, IPV6_SERVICE.vpnInfo = getVpnStatus(service_name, proto_name)
                ret.status = {
                    uid = IPV6_SERVICE.uid,
                    vpn = IPV6_SERVICE.vpnInfo,
                    vpnserver = IPV6_SERVICE.vpn_server,
                }
                logger("turbo_ipv6 status: " .. LuciJson.encode(ret.status))
                conn:reply(req, ret)
            end, {}
        },

        --
        event_update = {
            function(req, msg)
                local ret = { code = 0, msg = 'nothing act.' }
                local evt = msg.event
                if evt == 'connected' then -- V6 VPN is connected, update DNS etc
                    if IPV6_SERVICE.vpn_server and IPV6_SERVICE.vpn_server.dns and IPV6_SERVICE.vpn_server.dns ~= ''
                    then
                        IPV6_SERVICE.update_ipv6_dns(IPV6_SERVICE.vpn_server.dns)
                    end
                    update_ipv6(service_name, true)

                    IPV6_SERVICE.apply_route_iplist()
                    ret.msg = 'on firewall/dns for connect ipv6 VPN'
                elseif evt == 'disconnected' then -- V6 VPN is disconnected
                    IPV6_SERVICE.update_ipv6_dns(nil)
                    update_ipv6(service_name, false)
                    IPV6_SERVICE.clean_route_iplist()
                    ret.msg = 'off firewall/dns for disconnect ipv6 VPN'
                end
                conn:reply(req, ret)
            end, {}
        },

        --
        get_pass = {
            function(req)
                local ret = { code = 0, msg = 'ok' }
                _, IPV6_SERVICE.vpnInfo = getVpnStatus(service_name, proto_name)
                ret.status = {
                    uid = IPV6_SERVICE.uid,
                    vpn = IPV6_SERVICE.vpnInfo,
                    usage = IPV6_SERVICE.usageInfo,
                    vpnserver = IPV6_SERVICE.vpn_server,
                    ppplog = IPV6_SERVICE.get_ppplog(),
                    ifconfig = IPV6_SERVICE.get_ifconfig(),
                    ip6_data = IPV6_SERVICE.get_ip6_data()
                }
                logger("turbo_ipv6 status: " .. LuciJson.encode(ret.status))
                conn:reply(req, ret)
            end, {}
        }
    },
}

--try to start ccgame service
local function main_service()
    logger("ipv6 service ubus binding....")
    conn:add(ipv6_method)
    IPV6_SERVICE.init()
    uloop.run()
end

-- main
main_service()

