
local uci = require("luci.model.uci").cursor("/usr/share/xiaoqiang/")
local extendwifi = require("xiaoqiang.module.XQExtendWifi")

local peer_ip = arg[1]
local rom = uci:get("xiaoqiang_version","version","ROM")
local channel = uci:get("xiaoqiang_version","version","CHANNEL")
local hardware = uci:get("xiaoqiang_version","version","HARDWARE")
local mac = string.sub(luci.util.exec("getmac"),1,-2)
local sn = luci.util.exec("nvram get SN")

print("peer_ip:"..peer_ip.." rom:"..rom.." channel:"..channel.." hardware:"..hardware.." mac:"..mac.." sn:"..sn)
local sign_str="channel%3D"..channel.."%26hardware%3D"..hardware.."%26mac%3D"..mac.."%26rom%3D"..rom.."%26sn%3D"..sn
print(sign_str)
local params = "sign_str="..sign_str
print("params:"..params)
ret = extendwifi.ExtenWifiRequestRemoteAPI_(peer_ip,"/api/xqsystem/extendwifi_sign_for_auto_band","",params)

if ret.code ~= 0 then
	print("http get error")
	return 1
end

json = require("json")
res = json.decode(ret.msg)

if res.code ~= 0 then
	print("get sign error msg:"..res.msg)
	return 2
end

print("get sign str:"..res.signed_str.." deviceid:"..res.deviceid)

return 0

