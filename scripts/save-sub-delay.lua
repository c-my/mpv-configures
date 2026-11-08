-- 自动记住每个文件的 sub-delay（字幕延时），下次打开同一个文件时自动恢复。
--
-- 数据保存在 ~~/mpv-sub-delay.json，~~ 跟随 --config-dir。
-- 脚本不绑定按键，只监听 sub-delay 的变化并落盘，键位仍由 input.conf 决定。

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- ~~ = 当前 mpv 配置目录（受 --config-dir 影响）
local DATA_FILE = mp.command_native({'expand-path', '~~/mpv-sub-delay.json'})

local delays = {}
local current_path = nil
local restoring = false
local last_value = nil

local function load_data()
    local f = io.open(DATA_FILE, 'r')
    if not f then return end
    local content = f:read('*a')
    f:close()
    if not content or content == '' then return end
    local parsed = utils.parse_json(content)
    if type(parsed) == 'table' then
        delays = parsed
    else
        msg.warn('解析失败，忽略 ' .. DATA_FILE)
    end
end

local function save_data()
    local json = utils.format_json(delays)
    if not json then return end
    local f = io.open(DATA_FILE, 'w')
    if not f then
        msg.warn('无法写入 ' .. DATA_FILE)
        return
    end
    f:write(json)
    f:close()
end

-- 换文件时，mpv 会把 sub-delay 重置，这期间的变化不记录，
-- 否则会先把上次存的值覆盖成 0。
mp.register_event('start-file', function()
    restoring = true
    current_path = mp.get_property('path')
end)

mp.register_event('file-loaded', function()
    current_path = mp.get_property('path')
    local saved = current_path and delays[current_path]
    if saved and math.abs(saved) > 0.000999 then
        mp.set_property_native('sub-delay', saved)
        msg.verbose(('恢复 sub-delay=%.2f'):format(saved))
    end
    -- 换文件时 mpv 会把 sub-delay 重置成 0，那次变化发生在 file-loaded 之前，
    -- 已经靠 restoring 挡掉了；到这里就恢复监听。
    restoring = false
end)

mp.observe_property('sub-delay', 'number', function(_, value)
    if restoring or not current_path or not value then return end
    last_value = value
    delays[current_path] = value
    save_data()
end)

mp.register_event('shutdown', function()
    if current_path and last_value and not restoring then
        delays[current_path] = last_value
        save_data()
    end
end)

load_data()
