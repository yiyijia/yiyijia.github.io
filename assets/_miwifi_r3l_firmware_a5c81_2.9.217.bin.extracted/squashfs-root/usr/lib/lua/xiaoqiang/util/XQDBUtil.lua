module ("xiaoqiang.util.XQDBUtil", package.seeall)

local suc, SQLite3 = pcall(require, "lsqlite3")
local XQ_DB = "/etc/xqDb"
local uci = require("luci.model.uci").cursor()

-- --
-- -- |TABLE| USER_INFO(UUID,NAME,ICONURL)
-- -- |TABLE| PASSPORT_INFO(UUID,TOKEN,STOKEN,SID,SSECURITY)
-- -- |TABLE| DEVICE_INFO(MAC,ONAME,NICKNAME,COMPANY,OWNNERID)
-- --

-- function savePassport(uuid,token,stoken,sid,ssecurity)
--     local db = SQLite3.open(XQ_DB)
--     local fetch = string.format("select * from PASSPORT_INFO where UUID = '%s'",uuid)
--     local exist = false
--     for row in db:rows(fetch) do
--         if row then
--             exist = true
--         end
--     end
--     local sqlStr
--     if not exist then
--         sqlStr = string.format("insert into PASSPORT_INFO values('%s','%s','%s','%s','%s')",uuid,token,stoken,sid,ssecurity)
--     else
--         sqlStr = string.format("update PASSPORT_INFO set UUID = '%s', TOKEN = '%s', STOKEN = '%s', SID = '%s', SSECURITY = '%s' where UUID = '%s'",uuid,token,stoken,sid,ssecurity,uuid)
--     end
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function fetchPassport(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from PASSPORT_INFO where UUID = '%s'",uuid)
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["token"] = row[2],
--                 ["stoken"] = row[3],
--                 ["sid"] = row[4],
--                 ["ssecurity"] = row[5]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function fetchAllPassport()
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = "select * from PASSPORT_INFO"
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["token"] = row[2],
--                 ["stoken"] = row[3],
--                 ["sid"] = row[4],
--                 ["ssecurity"] = row[5]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function deletePassport(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from PASSPORT_INFO where UUID = '%s'",uuid)
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function saveUserInfo(uuid,name,iconUrl)
--     local db = SQLite3.open(XQ_DB)
--     local fetch = string.format("select * from USER_INFO where UUID = '%s'",uuid)
--     local exist = false
--     for row in db:rows(fetch) do
--         if row then
--             exist = true
--         end
--     end
--     local sqlStr
--     if not exist then
--         sqlStr = string.format("insert into USER_INFO values('%s','%s','%s')",uuid,name,iconUrl)
--     else
--         sqlStr = string.format("update USER_INFO set UUID = '%s', NAME = '%s', ICONURL = '%s' where UUID = '%s'",uuid,name,iconUrl,uuid)
--     end
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function fetchUserInfo(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from USER_INFO where UUID = '%s'",uuid)
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["name"] = row[2],
--                 ["iconUrl"] = row[3]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function fetchAllUserInfo()
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from USER_INFO")
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["name"] = row[2],
--                 ["iconUrl"] = row[3]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function deleteUserInfo(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from USER_INFO where UUID = '%s'",uuid)
--     db:exec(sqlStr)
--     return db:close()
-- end

local LuciDatatypes = require("luci.cbi.datatypes")

function conf_saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    if not LuciDatatypes.macaddr(mac) then
        return false
    end
    local key = mac:gsub(":", "").."_INFO"
    local section = {
        ["mac"] = mac,
        ["oname"] = oNmae,
        ["nickname"] = nickname,
        ["company"] = company
    }
    uci:section("devicelist", "deviceinfo", key, section)
    return uci:commit("devicelist")
end

function saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    if not suc then
        return conf_saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local fetch = string.format("select * from DEVICE_INFO where MAC = '%s'",mac)
    local exist = false
    for row in db:rows(fetch) do
        if row then
            exist = true
        end
    end
    local sqlStr
    if not exist then
        sqlStr = string.format("insert into DEVICE_INFO values('%s','%s','%s','%s','%s')",mac,oName,nickname,company,ownnerId)
    else
        sqlStr = string.format("update DEVICE_INFO set MAC = '%s', ONAME = '%s', NICKNAME = '%s', COMPANY = '%s', OWNNERID = '%s' where MAC = '%s'",mac,oName,nickname,company,ownnerId,mac)
    end
    db:exec(sqlStr)
    return db:close()
end

function conf_updateDeviceNickname(mac, nickname)
    if not LuciDatatypes.macaddr(mac) then
        return false
    end
    local key = mac:gsub(":", "").."_INFO"
    if uci:get_all("devicelist", key) then
        return uci:set("devicelist", "key", "nickname", nickname)
    end
    return false
end

function updateDeviceNickname(mac,nickname)
    if not suc then
        return conf_updateDeviceNickname(mac, nickname)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("update DEVICE_INFO set NICKNAME = '%s' where MAC = '%s'",nickname,mac)
    db:exec(sqlStr)
    return db:close()
end

-- function updateDeviceOwnnerId(mac,ownnerId)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("update DEVICE_INFO set OWNNERID = '%s' where MAC = '%s'",ownnerId,mac)
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function updateDeviceCompany(mac,company)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("update DEVICE_INFO set COMPANY = '%s' where MAC = '%s'",company,mac)
--     db:exec(sqlStr)
--     return db:close()
-- end

function conf_fetchDeviceInfo(mac)
    if not LuciDatatypes.macaddr(mac) then
        return {}
    end
    local key = mac:gsub(":", "").."_INFO"
    local info = uci:get_all("devicelist", key)
    if info then
        return {
            ["mac"] = info.mac or "",
            ["oName"] = info.oname or "",
            ["nickname"] = info.nickname or "",
            ["company"] = info.company or "",
            ["ownnerId"] = ""
        }
    end
    return {}
end

function fetchDeviceInfo(mac)
    if not suc then
        return conf_fetchDeviceInfo(mac)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("select * from DEVICE_INFO where MAC = '%s'",mac)
    local result = {}
    for row in db:rows(sqlStr) do
        if row then
            result = {
                ["mac"] = row[1],
                ["oName"] = row[2],
                ["nickname"] = row[3],
                ["company"] = row[4],
                ["ownnerId"] = row[5]
            }
        end
    end
    db:close()
    return result
end

function conf_fetchAllDeviceInfo()
    local result = {}
    uci:foreach("devicelist", "deviceinfo",
        function(s)
            table.insert(result, {
                ["mac"] = s.mac or "",
                ["oName"] = s.oname or "",
                ["nickname"] = s.nickname or "",
                ["company"] = s.company or "",
                ["ownnerId"] = ""
            })
        end
    )
    return result
end

function fetchAllDeviceInfo()
    if not suc then
        return conf_fetchAllDeviceInfo()
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("select * from DEVICE_INFO")
    local result = {}
    for row in db:rows(sqlStr) do
        if row and LuciDatatypes.macaddr(row[1]) then
            table.insert(result,{
                ["mac"] = row[1],
                ["oName"] = row[2],
                ["nickname"] = row[3],
                ["company"] = row[4],
                ["ownnerId"] = row[5]
            })
        end
    end
    db:close()
    return result
end

-- function deleteDeviceInfo(mac)
--     if not suc then
--         return
--     end
--     if not LuciDatatypes.macaddr(mac) then
--         return
--     end
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from DEVICE_INFO where MAC = '%s'",mac)
--     db:exec(sqlStr)
--     return db:close()
-- end
