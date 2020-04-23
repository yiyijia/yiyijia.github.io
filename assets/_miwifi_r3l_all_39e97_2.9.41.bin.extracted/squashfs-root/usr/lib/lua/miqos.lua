#!/usr/bin/lua


local px =  require "Posix"
local json= require 'json'
-- here interface for QOS-FIX-version
QOS_VER='FIX'

module("miqos", package.seeall)

function cmd(action)

    require "miqos.common"
    require "miqos.command"
    require "miqos.rule_by_service"

    cur_qdisc='service'
    local qos_cmd='/usr/sbin/miqosd fix'
    local args=string.split(action,' ')
    local res={status=4, data='unkown error.'}
    if lock() then
        logger(3,'[QOS_CMD]: miqos '..action..'')
        read_qos_config()
        if qdisc[cur_qdisc] and qdisc[cur_qdisc].read_qos_config then
            qdisc[cur_qdisc].read_qos_config()
        end
        cfg.qos_type.mode = "service"  -- 强制为service模式
        res,execflag = process_cmd(unpack(args))

        if execflag then    -- 更新qos规则
            os.execute(qos_cmd)
        end
        unlock()

    else
        res={status=2,data='command already in running.'}
    end

    return res
end

--[[ UNIT TEST
local function print_r(root,ind,printf)
    local indent="    " .. ind

    if not printf then printf = logger end

    for k,v in pairs(root or {}) do
            if(type(v) == "table") then
                    printf(3,indent .. k .. " = {")
                    print_r(v,indent,printf)
                    printf(3, indent .. "}")
            elseif(type(v) == "boolean") then
                local tmp = 'false'
                if v then tmp = 'true' end
                printf(3, indent .. k .. '=' .. tmp)
            else
                printf(3, indent .. k .. "=" .. v)
            end
    end
end

local function pr(root)
    print_r(root,'')
end

local function pr_console(root)
    print_r(root,'',print)
end

local function test_cmd(c)
    print('==================')
    print('[CMD]: ' .. c)
    pr_console(cmd(c))
    px.sleep(6)
    print('==================')
    print('')
end
test_cmd('off')
test_cmd('on')
test_cmd('on_limit max 08:9E:01:D0:F0:E2 500 500')
test_cmd('on_limit max 08:9E:01:D0:F0:E2 0 0')
test_cmd('show_cfg')
test_cmd('on_guest 50 400')
test_cmd('show_guest')
test_cmd('get_seq')
test_cmd('set_seq download,game,web,video')
test_cmd('show_limit')
test_cmd('show_guest')
test_cmd('show_band')
test_cmd('change_band 2000 2000')
test_cmd('show_band 0 0')
--]]




