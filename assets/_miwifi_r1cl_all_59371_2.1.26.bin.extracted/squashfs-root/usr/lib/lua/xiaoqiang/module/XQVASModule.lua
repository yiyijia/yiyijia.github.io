module ("xiaoqiang.module.XQVASModule", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local uci = require("luci.model.uci").cursor()
local lutil = require("luci.util")

function vas_info(conf)
    local info = {}
    if conf ~= "vas" and conf ~= "vas_user" then
        return info
    end
    local services = uci:get_all(conf, "services")
    if services then
        for k, v in pairs(services) do
            if not k:match("^%.") then
                v = tonumber(v)
                if v and v == -1 then
                    local cmd = uci:get("vas", k, "status")
                    if XQFunction.isStrNil(cmd) then
                        v = 1
                    else
                        local va = lutil.exec(cmd)
                        if va then
                            va = lutil.trim(va)
                            v = tonumber(va) or 1
                        else
                            v = 0
                        end
                    end
                end
                info[k] = v
            end
        end
    end
    return info
end

function get_new_vas()
    local info = {}
    local vas = vas_info("vas")
    local vas_user = vas_info("vas_user")
    if not vas then
        return info
    end
    for k, v in pairs(vas) do
        if v and not vas_user[k] then
            info[k] = v
        end
    end
    return info
end

function get_vas()
    local info = {}
    local vas = vas_info("vas")
    local vas_user = vas_info("vas_user")
    if not vas then
        return info
    end
    for k, v in pairs(vas) do
        if v and not vas_user[k] then
            info[k] = v
        else
            info[k] = vas_user[k]
        end
    end
    return info
end

function get_vas_kv_info()
    local info = {
        ["invalid_page_status"]     = "off",
        ["security_page_status"]    = "off",
        ["gouwudang_status"]        = "off"
    }
    local vasinfo = get_vas()
    if vasinfo.invalid_page and tonumber(vasinfo.invalid_page) == 1 then
        info.invalid_page_status = "on"
    end
    if vasinfo.security_page and tonumber(vasinfo.security_page) == 1 then
        info.security_page_status = "on"
    end
    if vasinfo.shopping_bar and tonumber(vasinfo.shopping_bar) == 1 then
        info.gouwudang_status = "on"
    end
    return info
end

function set_vas(info)
    if not info or type(info) ~= "table" then
        return false
    end
    local vas = vas_info("vas")
    local vas_user = vas_info("vas_user")
    for k, v in pairs(info) do
        vas_user[k] = v
        local cmd
        if v == 1 then
            cmd = uci:get("vas", k, "on")
        else
            cmd = uci:get("vas", k, "off")
        end
        if cmd then
            XQFunction.forkExec(cmd)
        end
    end
    uci:section("vas_user", "settings", "services", vas_user)
    uci:commit("vas_user")
end