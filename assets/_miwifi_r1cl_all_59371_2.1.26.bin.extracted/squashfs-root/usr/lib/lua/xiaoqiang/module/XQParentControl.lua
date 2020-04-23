module ("xiaoqiang.module.XQParentControl", package.seeall)

local XQFunction    = require("xiaoqiang.common.XQFunction")
local XQConfigs     = require("xiaoqiang.common.XQConfigs")

local bit   = require("bit")
local math  = require("math")

local uci   = require("luci.model.uci").cursor()
local lutil = require("luci.util")
local datatypes = require("luci.cbi.datatypes")

local LIMIT = 5  -- < 64

local WEEKDAYS = {
    ["Mon"] = 1,
    ["Tue"] = 2,
    ["Wed"] = 3,
    ["Thu"] = 4,
    ["Fri"] = 5,
    ["Sat"] = 6,
    ["Sun"] = 7
}

local WEEK = {
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun"
}

function get_global_info()
    local global = uci:get_all("parentalctl", "global")
    local info = {
        ["on"] = 1
    }
    if global then
        if global.disabled and tonumber(global.disabled) == 1 then
            info.on = 0
        end
    end
    return info
end

function get_macfilter_wan(mac)
    local wanper = true
    local data = lutil.exec("/usr/sbin/sysapi macfilter get | grep \""..string.lower(mac).."\"")
    if data then
        data = lutil.trim(data)
        data = data..";"
        local wan = data:match('wan=(%S-);')
        if wan and wan ~= "yes" then
            wanper = false
        end
    end
    return wanper
end

-- @param wan:true/false
-- true, macfilter wan=yes
-- false, macfilter wan=no
function macfilter_wan_changed(mac, wan)
    local key = mac:gsub(":", "")
    local count = 0
    local mark = 0
    uci:foreach("parentalctl", "device",
        function(s)
            count = count + 1
            if s[".name"]:match("^"..key) then
                if wan then
                    uci:set("parentalctl", s[".name"], "disabled", "1")
                else
                    if s.weekdays and s.time_seg and s.time_seg == "00:00-23:59" then
                        local weekdays = lutil.split(s.weekdays, " ")
                        if #weekdays == 7 then
                            mark = 1
                            uci:set("parentalctl", s[".name"], "disabled", "0")
                        end
                    end
                    if mark == 0 then
                        if tonumber(s.disabled) == 1 then
                            mark = s[".name"]
                        end
                    end
                    if count == 5 and mark == 0 then
                        mark = s[".name"]
                    end
                end
            end
        end
    )
    if not wan then
        local section = {
            ["mac"] = mac,
            ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
            ["disabled"] =  0,
            ["time_seg"] = "00:00-23:59"
        }
        if mark == 0 then
            local key = _generate_key(mac)
            uci:section("parentalctl", "device", key, section)
        elseif mark == 1 then
            -- do nothing.
        else
            uci:delete("parentalctl", mark)
            uci:section("parentalctl", "device", mark, section)
        end
    end
    uci:commit("parentalctl")
    apply()
end

-- Compatible sysapi/macfilter function
function parentctl_rule_changed(mac)
    local key = mac:gsub(":", "")
    local wanper = get_macfilter_wan(mac)
    local rule7 = false
    uci:foreach("parentalctl", "device",
        function(s)
            if s[".name"]:match("^"..key) and s.weekdays and s.time_seg and s.time_seg == "00:00-23:59" then
                local weekdays = lutil.split(s.weekdays, " ")
                if #weekdays == 7 then
                    if tonumber(s.disabled) == 0 then
                        rule7 = true
                    end
                end
            end
        end
    )
    if datatypes.macaddr(mac) then
        if rule7 and wanper then
            os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=no; /usr/sbin/sysapi macfilter commit")
        elseif not rule7 and not wanper then
            os.execute("/usr/sbin/sysapi macfilter set mac="..mac.." wan=yes; /usr/sbin/sysapi macfilter commit")
        end
    end
end

function _generate_key(mac)
    local key = mac:gsub(":", "")
    local flag = math.pow(2, LIMIT) - 1
    uci:foreach("parentalctl", "device",
        function(s)
            if s[".name"]:match("^"..key) then
                local ind = s[".name"]:gsub(key.."_", "")
                local ind = tonumber(ind)
                if ind and ind <= LIMIT then
                    flag = bit.bxor(flag, math.pow(2, ind - 1))
                end
            end
        end
    )
    for i = 1, LIMIT do
        if bit.band(flag, math.pow(2, i - 1)) > 0 then
            return key.."_"..tostring(i)
        end
    end
    return nil
end

function _parse_frequency(frequency, timeseg)
    local days = {}
    for _, day in ipairs(frequency) do
        if tonumber(day) == 0 then
            days = nil
            break
        end
        local day = WEEK[tonumber(day)]
        if day then
            table.insert(days, day)
        end
    end
    local start, stop
    if days then
        days = table.concat(days, " ")
    else
        start = os.date("%Y-%m-%d")
        stop = os.date("%Y-%m-%d", os.time() + 86400)
        if not XQFunction.isStrNil(timeseg) then
            local ctime = os.date("%X"):gsub(":%d+$", "")
            local entseg = timeseg:match("[%d:]+%-([%d:]+)")
            if ctime > entseg then
                start = os.date("%Y-%m-%d", os.time() + 86400)
                stop = os.date("%Y-%m-%d", os.time() + 2*86400)
            end
        end
    end
    return days, start, stop
end

function apply(async)
    if async then
        XQFunction.forkExec("/usr/sbin/parentalctl.sh 2>/dev/null >/dev/null")
    else
        os.execute("/usr/sbin/parentalctl.sh 2>/dev/null >/dev/null")
    end
end

function get_device_info(mac)
    if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    local info = {}
    local key = mac:gsub(":", "")
    local ctime = os.date("%X"):gsub(":%d+$", "")
    local cday = os.date("%Y-%m-%d")
    uci:foreach("parentalctl", "device",
        function(s)
            if s[".name"]:match("^"..key) then
                local item = {
                    ["id"] = s[".name"],
                    ["mac"] = s.mac,
                    ["enable"] = tonumber(s.disabled) == 1 and 0 or 1
                }
                local entseg
                if s.time_seg then
                    entseg = s.time_seg:match("[%d:]+%-([%d:]+)")
                end
                if s.start_date and s.stop_date then
                    item["frequency"] = {0}
                    if item.enable == 1 and (cday > s.start_date or (cday == s.start_date and ctime > entseg) or not entseg) then
                        item["enable"] = 0
                        uci:set("parentalctl", s[".name"], "disabled", 1)
                    end
                end
                if s.weekdays then
                    local fre = {}
                    local weekdays = lutil.split(s.weekdays, " ")
                    for _, day in ipairs(weekdays) do
                        table.insert(fre, WEEKDAYS[day])
                    end
                    item["frequency"] = fre
                end
                if s.time_seg then
                    local from, to = s.time_seg:match("([%d:]+)%-([%d:]+)")
                    if from and to then
                        item["timeseg"] = {
                            ["from"] = from,
                            ["to"] = to
                        }
                    end
                end
                table.insert(info, item)
            end
        end
    )
    local mark = uci:get_all("parentalctl", "mark")
    if not mark then
        mark = false
        uci:section("parentalctl", "record", "mark", {[key] = 1})
    else
        if mark[key] then
            mark = true
        else
            mark = false
            uci:set("parentalctl", "mark", key, 1)
        end
    end
    uci:commit("parentalctl")
    if #info > 0 then
        return info
    else
        if not mark then
            local wanper = get_macfilter_wan(mac)
            local key = _generate_key(mac)
            local section = {
                ["mac"] = mac,
                ["weekdays"] = "Mon Tue Wed Thu Fri Sat Sun",
                ["disabled"] = wanper and 1 or 0,
                ["time_seg"] = "00:00-23:59"
            }
            uci:section("parentalctl", "device", key, section)
            uci:commit("parentalctl")
            local inf = {
                ["id"] = key,
                ["mac"] = mac,
                ["frequency"] = {1,2,3,4,5,6,7},
                ["enable"] = wanper and 0 or 1,
                ["timeseg"] = {
                    ["from"] = "00:00",
                    ["to"] = "23:59"
                }
            }
            table.insert(info, inf)
            return info
        else
            return nil
        end
    end
end

function add_device_info(mac, enable, frequency, timeseg)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(mac)
        or not frequency or type(frequency) ~= "table"
        or XQFunction.isStrNil(timeseg)
        or not timeseg:match("[%d:]+%-[%d:]+") then
        return false
    else
        mac = XQFunction.macFormat(mac)
    end
    local key = _generate_key(mac)
    if not key then
        return false
    end
    local days, start, stop = _parse_frequency(frequency)
    local section = {
        ["mac"] = mac,
        ["weekdays"] = days,
        ["start_date"] = start,
        ["stop_date"] = stop,
        ["disabled"] = (enable == 1) and 0 or 1,
        ["time_seg"] = timeseg
    }
    uci:section("parentalctl", "device", key, section)
    uci:commit("parentalctl")
    parentctl_rule_changed(mac)
    XQSync.syncDeviceInfo({["mac"] = mac})
    return key
end

function update_device_info(id, mac, enable, frequency, timeseg)
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    if XQFunction.isStrNil(id) then
        return false
    end
    local section = uci:get_all("parentalctl", id)
    if not section then
        return false
    end
    if enable then
        section["disabled"] = (enable == 1) and 0 or 1
    end
    if frequency then
        local days, start, stop = _parse_frequency(frequency, timeseg or section.time_seg)
        if days then
            section["weekdays"] = days
            section["start_date"] = nil
            section["stop_date"] = nil
            uci:delete("parentalctl", id, "start_date")
            uci:delete("parentalctl", id, "stop_date")
        end
        if start then
            section["start_date"] = start
        end
        if stop then
            section["stop_date"] = stop
        end
        if start or stop then
            section["weekdays"] = nil
            uci:delete("parentalctl", id, "weekdays")
        end
    else
        if enable and enable == 1 and section.start_date and section.stop_date then
            local days, start, stop = _parse_frequency({0}, timeseg or section.time_seg)
            if start then
                section["start_date"] = start
            end
            if stop then
                section["stop_date"] = stop
            end
        end
    end
    if timeseg and timeseg:match("[%d:]+%-[%d:]+") then
        section["time_seg"] = timeseg
    end
    uci:section("parentalctl", "device", id, section)
    uci:commit("parentalctl")
    parentctl_rule_changed(mac)
    XQSync.syncDeviceInfo({["mac"] = mac})
    return true
end

function delete_device_info(id)
    if XQFunction.isStrNil(id) then
        return false
    end
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local sec = uci:get_all("parentalctl", id)
    local mac
    if sec then
        mac = sec.mac
    end
    uci:delete("parentalctl", id)
    uci:commit("parentalctl")
    if mac then
        parentctl_rule_changed(mac)
    end
    XQSync.syncDeviceInfo({["mac"] = mac})
    return true
end

-- macs: nil or {["XX:XX:XX:XX:XX:XX"] = 1,...}
function parentctl_rules(macs)
    local rules = {}
    uci:foreach("parentalctl", "device",
        function(s)
            if s.mac then
                if not macs or (macs and macs[s.mac]) then
                    local rule = rules[s.mac]
                    if rule then
                        rule.total = rule.total + 1
                        if s.disabled and tonumber(s.disabled) == 0 then
                            rule.enabled = rule.enabled + 1
                        end
                    else
                        rule = {
                            ["total"] = 1,
                            ["enabled"] = 0
                        }
                        if s.disabled and tonumber(s.disabled) == 0 then
                            rule.enabled = 1
                        end
                    end
                    rules[s.mac] = rule
                end
            end
        end
    )
    if macs then
        for mac, value in pairs(macs) do
            if not rules[mac] then
                rules[mac] = {
                    ["total"] = 0,
                    ["enabled"] = 0
                }
            end
        end
    end
    return rules
end
