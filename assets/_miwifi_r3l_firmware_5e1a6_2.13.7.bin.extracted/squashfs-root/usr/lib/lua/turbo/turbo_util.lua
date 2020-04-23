#!/usr/bin/lua
--[[
ipv6 turbo service deamon program
Author: MIWIFI@2017
--]]

--module("turbo.turbo_util", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local Network = require("luci.model.network")
local Firewall = require("luci.model.firewall")
local x = uci.cursor()
local LuciUtil = require("luci.util")
local LuciJson = require("cjson")
local px = require "posix"
local turbo = require "libturbo"

math.randomseed(os.time())

function logerr(msg)
    if g_debug then
        print(msg)
    else
        px.syslog(3, msg)
    end
end

function logger(msg)
    if g_debug then
        print(msg)
    else
        --px.syslog(7, msg)
    end
end

--read uci config
function read_cfg(conf, type, opt, default)
    local val = x:get(conf, type, opt) or default
    return val or ""
end

--write uci config
function write_cfg(conf, type, opt, value)
    if value then
        x:set(conf, type, opt, value)
    else
        x:delete(conf, type, opt)
    end
    x:commit(conf)
end

function exec_cmd_t(command)
    local pp = io.popen(command)
    local data = {}

    while true do
        local line = pp:read()
        if not line then
            break
        end
        data[#data + 1] = line
    end
    pp:close()

    return data
end

function exec_cmd_s(command)
    local pp = io.popen(command)
    local data = pp:read("*a")
    pp:close()

    return data
end

function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

function split(str, pat, max, regex)
    pat = pat or "\n"
    max = max or #str

    local t = {}
    local c = 1

    if #str == 0 then
        return { "" }
    end

    if #pat == 0 then
        return nil
    end

    if max == 0 then
        return str
    end

    repeat
        local s, e = str:find(pat, c, not regex)
        max = max - 1
        if s and max < 0 then
            t[#t + 1] = str:sub(c)
        else
            t[#t + 1] = str:sub(c, s and s - 1)
        end
        c = e and e + 1 or #str + 1
    until not s or max < 0

    return t
end

--
function update_ipv6(ifname, on)
    if not ifname or ifname == '' then
        return
    end
    if on then
        addVpnFirewall(ifname, "wan")
        LuciUtil.exec("fw3 reload >/dev/null 2>&1")
    else
        delVpnFirewall(ifname, "wan")
        LuciUtil.exec("fw3 reload >/dev/null 2>&1")
    end
end


function addVpnFirewall(service, zone)
    local firewall = Firewall.init()
    local zoneWan = firewall:get_zone(zone)
    zoneWan:add_network(service)
    firewall:save("firewall")
    firewall:commit("firewall")
end


function delVpnFirewall(service, zone)
    -- clean firewall
    local firewall = Firewall.init()
    local zoneWan = firewall:get_zone(zone)
    zoneWan:del_network(service)
    firewall:save("firewall")
    firewall:commit("firewall")
end



-- @param proto pptp/l2tp
local function setVpnIface(data)
    if XQFunction.isStrNil(data.service) or
            XQFunction.isStrNil(data.server) or
            XQFunction.isStrNil(data.username) or
            XQFunction.isStrNil(data.password) or
            XQFunction.isStrNil(data.proto) then

        logger("interface:" .. (data.service or "nil"))
        logger("server:" .. (data.server or "nil"))
        logger("username:" .. (data.username or "nil"))
        logger("password:" .. (data.password or "nil"))
        logger("proto:" .. (data.proto or "nil"))
        return nil
    end


    local protocal = string.lower(data.proto)
    local network = Network.init()
    network:del_network(data.service)

    local ifdata = {
        proto = protocal,
        server = data.server,
        username = data.username,
        password = data.password,
        auth = 'auto',
        auto = '0',
        pppd_options = 'refuse-eap',
        peerdns = data.peerdns or '0',
        defaultroute = '0',
        maxtries = data.maxtries or '0'
    }

    if data.dns and not XQFunction.isStrNil(data.dns) then
        ifdata.dns = { data.dns }
    end

    local vpnNetwork = network:add_network(data.service, ifdata)

    -- add ipv6 support
    local vpn6Network = false
    if data.ipv6 then
        network:del_network(data.service .. '6')
        vpn6Network = network:add_network(data.service .. '6', {
            proto = 'dhcpv6',
            ifname = '@' .. data.service,
            peerdns = data.peerdns6 or '0',
        })
    else
        vpn6Network = true
    end

    if vpnNetwork and vpn6Network then
        network:save("network")
        network:commit("network")
        return data.service
    end

    return nil
end

-- del vpn config in /etc/config/network
local function delVpnIface(interface)
    local service = interface
    local network = Network.init()
    network:del_network(service)
    network:del_network(service .. "6")
    network:save("network")
    network:commit("network")
end

function vpnOn(data)
    data.proto = 'l2tp'
    data.maxtries = '10'
    local ifname = setVpnIface(data)
    if ifname then
        os.execute("ifup " .. ifname)
        return true
    else
        logerr("create VPN interface " .. service .. " failed.")
        return false
    end
end

function vpnOff(service, delete_if)
    os.execute("ifdown " .. service)
    if delete_if then
        delVpnIface(service)
    end
end

function getVpnStatus(service, proto)
    local cmd = "ifconfig " .. proto .. "-" .. service .. " 2>/dev/null"
    --ifconfig l2tp-ccgame 2>/dev/null
    local res = {
        status = 0,
        ip = {},
        ip6 = {},
    }
    local ps = exec_cmd_t(cmd)
    if not ps then
        return -1
    end

    local isMatch = false
    for _, line in pairs(ps) do
        line = trim(line)
        local sec = split(line, '%s+', nil, true)
        if #sec > 0 then
            if sec[1] == 'l2tp-ipv6' then
                isMatch = true
            elseif sec[1] == 'inet' then
                local _ip, _ptp, _mask = string.match(line, "inet addr:(%d+.%d+.%d+.%d+)%s+P%-t%-P:(%d+.%d+.%d+.%d+)%s+Mask:(%d+.%d+.%d+.%d+)")
                res.ip[#res.ip + 1] = { ip = _ip, ptp = _ptp, mask = _mask }
            elseif sec[1] == 'inet6' then
                local _ip, _scope = string.match(line, "inet6 addr: ([^%s]+) Scope:([^%s]+)")
                res.ip6[#res.ip6 + 1] = { ip = _ip, scope = _scope }
            end
        end
    end

    if isMatch then
        res.status = 1
        return 0, res
    else
        res.status = 0
        return -2, res
    end
end

function update_auto_dns(close_peer_dns, restartif, skipif)
    local peerdns = '1' -- default value
    if close_peer_dns then
        peerdns = '0'
    end

    local network = Network.init()
    local nets = network:get_networks()
    for _, n in pairs(nets) do
        if skipif and n.sid and skipif[n.sid] then
            -- skip setting such skip-ifs
        else
            n:set('peerdns', peerdns)
        end
    end

    network:commit("network")

    -- restart interface after cfg changed.
    for _, ifname in pairs(restartif or {}) do
        logerr("NOTE: restart interface: " .. ifname .. " after change network peerdns config. ")
        --os.execute("ifup " .. ifname)
    end
end

function set_dev_fe80_rand_addr(ifname)
    if not ifname or ifname == '' then
        return;
    end
    local fe80_addr='fe80:'
    for i=1, 5 do
        fe80_addr = fe80_addr  .. ":" .. tostring(math.random(9999))
    end
    
    local cmd ='ip -6 a flush dev ' .. ifname;
    cmd = cmd .. ' && ip -6 a add ' .. fe80_addr .. ' dev ' .. ifname

    LuciUtil.exec(cmd);
    
end

function route_add_ipnet(setname, ipnet_array)
    -- flush ipset 1stly
    if not ipnet_array or #ipnet_array <= 0 then
        return -1
    end

    local res = {}
    if not turbo.ipset_open() then
        return -1
    end

    for _,v in ipairs(ipnet_array) do
        local sec = split(v, '/', nil, false)
        local ip,mask
        if sec[1] then ip = sec[1] end
        if sec[2] then mask = tonumber(sec[2]) else mask = 32 end
        --logger("add record: ip: " .. ip ..',mask:' .. mask)
        turbo.ipset_add_net(setname,ip,mask)
    end
    
    -- close turbo socket
    turbo.ipset_close()
    return 0
end


