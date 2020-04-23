local net = require("xiaoqiang.util.XQNetUtil")
local configs = require("xiaoqiang.common.XQConfigs")

local key = arg[1]

if key then
    os.execute("/usr/sbin/log_collection.sh")
    net.uploadLogFile(configs.LOG_ZIP_FILEPATH, "B", key)
end