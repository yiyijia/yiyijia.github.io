module ("xiaoqiang.module.XQWifiShare", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local LuciUtil = require("luci.util")

function wifi_share_info()
    local uci = require("luci.model.uci").cursor()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local info = {
        ["guest"] = 0,
        ["share"] = 0,
        ["sns"] = {}
    }
    local guest = wifi.getGuestWifi(1)
    info["guest"] = guest.status
    info["data"] = {
        ["ssid"] = guest.ssid,
        ["encryption"] = guest.encryption,
        ["password"] = guest.password
    }
    local disabled = uci:get("wifishare", "global", "disabled") or 1
    if disabled then
        info.share = tonumber(disabled) == 0 and 1 or 0
    end
    info.sns = uci:get_list("wifishare", "global", "sns") or {}
    return info
end

function set_wifi_share(info)
    if not info or type(info) ~= "table" then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    local guest = require("xiaoqiang.module.XQGuestWifi")
    if info.guest and info.share then
        local cmd = "/usr/sbin/wifishare.sh on"
        if info.share == 0 then
            cmd = "/usr/sbin/wifishare.sh off"
        end
        local function callback(networkrestart)
            if networkrestart then
                XQFunction.forkExec("sleep 4; /usr/sbin/guestwifi.sh open; "..cmd)
            else
                XQFunction.forkExec("sleep 4; /sbin/wifi >/dev/null 2>/dev/null; "..cmd)
            end
        end
        -- set wifi share
        if info.sns and type(info.sns) == "table" and #info.sns > 0 then
            uci:set_list("wifishare", "global", "sns", info.sns)
        end
        uci:set("wifishare", "global", "disabled", info.share == 1 and "0" or "1")
        uci:commit("wifishare")
        -- set guest wifi
        local ssid, encryption, key
        if info.data and type(info.data) == "table" then
            ssid = info.data.ssid
            encryption = info.data.encryption
            key = info.data.password
        end
        if info.share == 1 then
            encryption = "none"
        end
        guest.setGuestWifi(1, ssid, encryption, key, 1, info.guest, callback)
    end
    return true
end

-- config device 'D04F7EC0D55D'
--      option disbaled '0'
--      option mac 'D0:4F:7E:C0:D5:5D'
--      option state 'auth'
--      option start_date       2015-06-18
--      option timeout '3600'
--      option sns 'wechat'
--      option guest_user_id '24214185'
--      option extra_payload 'payload test'
function wifi_access(mac, sns, uid, grant, extra)
    local uci = require("luci.model.uci").cursor()
    if XQFunction.isStrNil(mac) then
        return false
    end
    local mac = XQFunction.macFormat(mac)
    local key = mac:gsub(":", "")
    local info = uci:get_all("wifishare", key)
    if info then
        info["mac"] = mac
        if not XQFunction.isStrNil(sns) then
            info["sns"] = sns
        end
        if not XQFunction.isStrNil(uid) then
            info["guest_user_id"] = uid
        end
        if not XQFunction.isStrNil(extra) then
            info["extra_payload"] = extra
        end
        if grant then
            if grant == 0 then
                info["disabled"] = "1"
            elseif grant == 1 then
                info["disabled"] = "0"
            end
        end
    else
        if XQFunction.isStrNil(sns) or XQFunction.isStrNil(uid) or not grant then
            return false
        end
        info = {
            ["mac"] = mac,
            ["state"] = "auth",
            ["sns"] = sns,
            ["guest_user_id"] = uid,
            ["extra_payload"] = extra,
            ["disabled"] = grant == 1 and "0" or "1"
        }
    end
    uci:section("wifishare", "device", key, info)
    uci:commit("wifishare")
    if grant then
        if grant == 0 then
            os.execute("/usr/sbin/wifishare.sh deny "..mac)
        elseif grant == 1 then
            os.execute("/usr/sbin/wifishare.sh allow "..mac)
        end
    end
    return true
end

-- only for testing
function wifi_share_clearall()
    local uci = require("luci.model.uci").cursor()
    uci:foreach("wifishare", "device",
        function(s)
            if s["mac"] then
                uci:delete("wifishare", s[".name"])
                os.execute("/usr/sbin/wifishare.sh deny "..s["mac"])
            end
        end
    )
    uci:commit("wifishare")
end

function sns_list(sns)
    local uci = require("luci.model.uci").cursor()
    local info = {}
    if XQFunction.isStrNil(sns) then
        return info
    end
    uci:foreach("wifishare", "device",
        function(s)
            if s["sns"] and s["sns"] == sns then
                if not s["disabled"] or tonumber(s["disabled"]) == 0 then
                    table.insert(info, s["guest_user_id"])
                end
            end
        end
    )
    return info
end