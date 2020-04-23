module("luci.controller.service.internal", package.seeall)

function index()
    local page   = node("service","internal")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = nil
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"service", "internal", "ccgame"}, call("turbo_ccgame_call"), (""), nil, 0x10)
    entry({"service", "internal", "ipv6"}, call("turbo_ipv6_call"), (""), nil, 0x01)
end

local LuciHttp = require("luci.http")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local ServiceErrorUtil = require("service.util.ServiceErrorUtil")
local XQFunction = require("xiaoqiang.common.XQFunction")
local LuciJson = require("cjson")
local LuciUtil = require("luci.util")

-- ccgame call interface
function turbo_ccgame_call()
    local cmd = tonumber(LuciHttp.formvalue("cmd") or "")
    local result={}
    local XQCCGame = require("turbo.ccgame.ccgame_interface")
    if not XQCCGame then
        result['code'] = -1
        result['msg'] = 'not support ccgame.'
    elseif cmd < 0 or cmd > 7 then
        result['code'] = -1
        result['msg'] = 'action id is not valid'
    else
        local para ={}
        para.cmdid = cmd
        para.data={}
        local strIPlist = LuciHttp.formvalue("ip")
        local strByVPN = LuciHttp.formvalue("byvpn")
        local strGame = LuciHttp.formvalue("game")
        local strRegion = LuciHttp.formvalue("region")
        local strUbus = LuciHttp.formvalue("ubus")

        if strIPlist then
            para.data['iplist'] = XQFunction._cmdformat(strIPlist)
        end
        if strByVPN and strByVPN ~= "0" then
            para.data['byvpn'] = "0"
        else
            para.data['byvpn'] = "1"
        end

        if strGame and strRegion then
            para.data['gameid'] = XQFunction._cmdformat(strGame)
            para.data['regionid'] = XQFunction._cmdformat(strRegion)
        end

        if strUbus then
            para.ubus = XQFunction._cmdformat(strUbus)
        end

        result = XQCCGame.ccgame_call(para)
    end
    LuciHttp.write_json(result)
end

-- turbo ipv6 interface
function turbo_ipv6_call()
    local cmd = tonumber(LuciHttp.formvalue("cmd") or "")
    local result={}
    if cmd < 0 or cmd > 3 then
        result['code'] = -1
        result['msg'] = 'action id is not valid'
    else
        local ubus = require("ubus")
        local conn = ubus.connect()
        if not conn then
            result['code'] = -1
            result['msg'] = 'ubus cannot connected.'
        else
            local query=nil
            local ubus_service = 'turbo_ipv6'
            local data={}
            if cmd == 1 then
                -- need active account 1stly
                local pdata={provider="sellon"}
                local cmd = "matool --method api_call_post --params /device/vip/account '" .. LuciJson.encode(pdata) .. "'"

                local ret, account = pcall(function() return LuciJson.decode(LuciUtil.trim(LuciUtil.exec(cmd))) end)

                if not ret or not account or type(account) ~= "table" or account.code ~= 0 then
                    result['code'] = -1
                    result['msg'] = 'active account failed. pls check if account binded or network is connected.'
                    query = nil
                else
                    query = 'start'
                end
            elseif cmd == 2 then
                query = 'stop'
            elseif cmd == 3 then
                query = 'status'
            elseif cmd == 0 then
                query = XQFunction._cmdformat(LuciHttp.formvalue("ubus") or "nothing")
            else
                query = nil
                result.msg = 'not supported command.'
            end

            if query and query ~= '' then
                local res = conn:call(ubus_service, query, data)
                conn:close()
                if res then
                    result = res
                else
                    result['code'] = -1
                    result['msg'] = 'call ubus failed.'
                end
            else
                result.code = -1
            end
        end
    end
    LuciHttp.write_json(result)
end
