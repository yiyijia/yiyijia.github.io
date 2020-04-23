module("luci.controller.api.misns", package.seeall)

function index()
    local page   = node("api","misns")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = 200
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"api", "misns"}, firstchild(), (""), 200)
    entry({"api", "misns", "prepare"},              call("prepare"), (""), 201, 0x01)
    entry({"api", "misns", "wifi_share_switch"},    call("wifiShare"), (""), 202)
    entry({"api", "misns", "wifi_access"},          call("wifiAccess"), (""), 203)
    entry({"api", "misns", "wifi_share_info"},      call("wifiShareInfo"), (""), 204)
    entry({"api", "misns", "sns_list"},             call("snsList"), (""), 205)
    entry({"api", "misns", "sns_init"},             call("snsInit"), (""), 206, 0x01)
    entry({"api", "misns", "wifi_share_clear"},     call("wifiShareClearAll"), (""), 207)
end

local LuciHttp      = require("luci.http")
local LuciDatatypes = require("luci.cbi.datatypes")
local XQConfigs     = require("xiaoqiang.common.XQConfigs")
local XQFunction    = require("xiaoqiang.common.XQFunction")
local XQErrorUtil   = require("xiaoqiang.util.XQErrorUtil")
local XQWifiShare   = require("xiaoqiang.module.XQWifiShare")

function wifiShareInfo()
    local result = {
        ["code"] = 0
    }
    result["info"] = XQWifiShare.wifi_share_info()
    LuciHttp.write_json(result)
end

function snsInit()
    local LuciUtil = require("luci.util")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local result = {
        ["code"] = 0,
        ["clientinfo"] = "",
        ["ssid"] = ""
    }
    local callback = LuciHttp.formvalue("callback")
    local mac = luci.dispatcher.getremotemac()
    local guest = XQWifiUtil.getGuestWifi(1)
    result.clientinfo = LuciUtil.trim(LuciUtil.exec(string.format("matool --method enc --params \"{\\\"mac\\\":\\\"%s\\\"}\"", mac)))
    result.ssid = guest.ssid
    LuciHttp.write_jsonp(result, callback)
end

function prepare()
    local result = {
        ["code"] = 0
    }
    local callback = LuciHttp.formvalue("callback")
    local mac = luci.dispatcher.getremotemac()
    os.execute("/usr/sbin/wifishare.sh prepare "..mac)
    LuciHttp.write_jsonp(result, callback)
end

-- enable : int, 0/1 关闭/开启
function wifiShare()
    local json = require("json")
    local result = {
        ["code"] = 0
    }
    local info = LuciHttp.formvalue("info")
    if XQFunction.isStrNil(info) then
        result.code = 1523
    else
        local suc, ninfo = pcall(json.decode, info)
        if not suc then
            result.code = 1523
        else
            XQWifiShare.set_wifi_share(ninfo)
        end
    end
    if result.code ~= 0 then
        result["msg"] = XQErrorUtil.getErrorMessage(result.code)
    end
    LuciHttp.write_json(result)
end

-- sns : string, 社交网络代码
-- guest_user_id : string, 好友id
-- extra_payload : string
-- mac : string, 放行设备mac地址
-- grant : int, 0/1 取消放行/放行
function wifiAccess()
    local result = {
        ["code"] = 0
    }
    local sns = LuciHttp.formvalue("sns")
    local guid = LuciHttp.formvalue("guest_user_id")
    local expayload = LuciHttp.formvalue("extra_payload")
    local mac = LuciHttp.formvalue("mac")
    local grant = tonumber(LuciHttp.formvalue("grant")) or 1
    if not mac or not LuciDatatypes.macaddr(mac) then
        result.code = 1523
    else
        XQWifiShare.wifi_access(mac, sns, guid, grant, expayload)
        if grant == 1 then
            local json = require("json")
            local push = require("xiaoqiang.XQPushHelper")
            local name = ""
            if not XQFunction.isStrNil(expayload) then
                local succ, info = pcall(json.decode, expayload)
                if succ and info then
                    name = info.nickname
                end
            end
            push._guestWifiConnectPush(mac, sns, name)
        end
    end
    if result.code ~= 0 then
        result["msg"] = XQErrorUtil.getErrorMessage(result.code)
    end
    LuciHttp.write_json(result)
end

function snsList()
    local sns = LuciHttp.formvalue("sns") or "weixin"
    local result = {
        ["code"] = 0
    }
    result["data"] = XQWifiShare.sns_list(sns)
    LuciHttp.write_json(result)
end

function wifiShareClearAll()
    local result = {
        ["code"] = 0
    }
    XQWifiShare.wifi_share_clearall()
    LuciHttp.write_json(result)
end