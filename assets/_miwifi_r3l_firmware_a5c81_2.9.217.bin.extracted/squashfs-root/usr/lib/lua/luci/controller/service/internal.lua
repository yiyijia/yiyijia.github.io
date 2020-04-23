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
