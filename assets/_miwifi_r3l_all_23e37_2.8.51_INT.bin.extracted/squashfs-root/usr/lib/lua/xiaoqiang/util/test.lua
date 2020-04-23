
local LuciProtocol = require("luci.http.protocol")
local DEFAULT_TOKEN = "8007236f-a2d6-4847-ac83-c49395ad6d65"

function cryptUrl(serverUrl, subUrl, params, salt)
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    if serverUrl == nil or params == nil then
        return nil
    end
    local time = "2020-04-16--18:28:06"--XQFunction.getTime()
    table.insert(params,{"time",time})
    table.sort(params, function(a, b) return a[1] < b[1] end)
    local str = ""
    table.foreach(params, function(k, v) str = str..v[1].."="..v[2].."&" end)
    if salt ~= nil and salt ~= "" then
        str = str .. salt
    end
    local md5 = XQCryptoUtil.md5Base64Str(str)
    local token = "8007236f-a2d6-4847-ac83-c49395ad6d65" --getToken()
    local url = ""
    if string.find(serverUrl..subUrl,"?") == nil then
        url = serverUrl..subUrl.."?s="..md5.."&time="..time.."&token="..LuciProtocol.urlencode(token)
    else
        url = serverUrl..subUrl.."&s="..md5.."&time="..time.."&token="..LuciProtocol.urlencode(token)
    end

    return url
end

local LuciJson = require("json")
local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
local XQPreference = require("xiaoqiang.XQPreference")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
local XQCountryCode = require("xiaoqiang.XQCountryCode")
local isrecovery = true
local params = {}

params = {
    {"deviceID", "aebe3331-9965-b15f-3369-9a11e530e843"},
    {"rom", "2.11.20"},
    {"hardware", "R3L"},
    {"cfe", "1.0.0"},
    {"linux", "0.0.1"},
    {"ramfs", "0.0.1"},
    {"sqafs", "0.0.1"},
    {"rootfs", "0.0.1"},
    {"channel", "stable"},
    {"serialNumber", "12939/20663686"}
}    
local query = {}
table.foreach(params, function(k, v) query[v[1]] = v[2] end)
local queryString = LuciProtocol.urlencode_params(query)
local subUrl = "/rs/grayupgrade/recovery".."?"..queryString
local requestUrl = cryptUrl("http://in.api.miwifi.com", subUrl, params, DEFAULT_TOKEN)
print(requestUrl)