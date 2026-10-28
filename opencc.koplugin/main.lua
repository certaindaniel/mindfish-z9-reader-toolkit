local Device = require("device")

if not Device.isAndroid() then
    return { disabled = true }
end

local Android = require("android")
local BaseUtil = require("ffi/util")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local Epub = require("opencc_epub")
local _ = require("gettext")

local PRIVATE_DIR = Android.dir .. "/opencc"
local BINARY_PATH = PRIVATE_DIR .. "/opencc"
local DATA_DIR = PRIVATE_DIR .. "/data"
local MAX_TEXT_FILE_SIZE = 64 * 1024 * 1024

local function fail(message)
    error(message, 0)
end

local function read_file(path, maximum)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then fail("The current book file cannot be read") end
    if attr.size > maximum then fail("This book is too large for the on-device converter") end
    local file, err = io.open(path, "rb")
    if not file then fail("Cannot open book: " .. tostring(err)) end
    local content = file:read("*a")
    file:close()
    if not content then fail("Cannot read the current book file") end
    return content
end

local function write_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then fail("Cannot write output file: " .. tostring(err)) end
    local ok, write_error = file:write(content)
    local close_ok, close_error = file:close()
    if not ok then fail("Cannot write output file: " .. tostring(write_error)) end
    if not close_ok then fail("Cannot finish output file: " .. tostring(close_error)) end
end

local function unique_suffix()
    return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function convert_utf8_text(text, scratch_dir, index)
    if text:find("%z") or not Epub.isValidUtf8(text) then
        fail("Only UTF-8 EPUB and TXT files can be converted")
    end
    local input_path = scratch_dir .. "/text-" .. tostring(index) .. ".in"
    local output_path = scratch_dir .. "/text-" .. tostring(index) .. ".out"
    os.remove(input_path)
    os.remove(output_path)

    local bom = ""
    if text:sub(1, 3) == "\239\187\191" then
        bom = text:sub(1, 3)
        text = text:sub(4)
    end
    write_file(input_path, text)
    local status = BaseUtil.execute(
        BINARY_PATH,
        "-c", "s2twp.json",
        "--path", DATA_DIR,
        "-i", input_path,
        "-o", output_path
    )
    if status ~= 0 then
        os.remove(input_path)
        os.remove(output_path)
        fail("OpenCC conversion failed (exit " .. tostring(status) .. ")")
    end
    local converted = read_file(output_path, MAX_TEXT_FILE_SIZE)
    os.remove(input_path)
    os.remove(output_path)
    if converted:find("%z") or not Epub.isValidUtf8(converted) then
        fail("OpenCC produced invalid UTF-8 output")
    end
    return bom .. converted
end

local function split_path(path)
    local directory, filename = path:match("^(.*)/([^/]*)$")
    if not directory then return ".", path end
    if directory == "" then directory = "/" end
    return directory, filename
end

local function output_path_for(source, extension)
    local directory, filename = split_path(source)
    local stem = filename:match("^(.*)%.[^%.]+$") or filename
    return directory .. "/" .. stem .. ".zh-TW." .. extension
end

local function convert_txt(source, destination, scratch_dir)
    if lfs.attributes(destination) then fail("The Traditional Chinese copy already exists") end
    local content = read_file(source, MAX_TEXT_FILE_SIZE)
    local suffix = unique_suffix()
    local partial = destination .. ".partial-" .. suffix
    if lfs.attributes(partial) then fail("Temporary conversion file already exists") end
    local ok, result = pcall(function()
        local converted = convert_utf8_text(content, scratch_dir, 1)
        write_file(partial, converted)
        local readback = read_file(partial, MAX_TEXT_FILE_SIZE)
        if readback ~= converted then fail("TXT output failed its read-back check") end
        if lfs.attributes(destination) then fail("The Traditional Chinese copy already exists") end
        local renamed, err = os.rename(partial, destination)
        if not renamed then fail("Cannot publish the converted TXT: " .. tostring(err)) end
        return destination
    end)
    if lfs.attributes(partial) then os.remove(partial) end
    if not ok then error(result, 0) end
    return result
end

local function display_name(path)
    local _, filename = split_path(path)
    return filename
end

local OpenCC = WidgetContainer:new{
    name = "opencc",
    is_doc_only = true,
}

function OpenCC:init()
    self.ui.menu:registerToMainMenu(self)
end

function OpenCC:getCurrentFormat()
    local path = self.ui.document and self.ui.document.file
    if not path then return nil end
    local _, filename = split_path(path)
    local extension = filename:match("%.([^%.]+)$")
    return extension and extension:lower() or nil
end

function OpenCC:isActionEnabled()
    local extension = self:getCurrentFormat()
    return extension == "epub" or extension == "txt"
end

function OpenCC:convertCurrentBook()
    if not self:isActionEnabled() then
        UIManager:show(InfoMessage:new{ text = _("目前只支援 EPUB 與 TXT。") })
        return
    end
    if lfs.attributes(BINARY_PATH, "mode") ~= "file"
            or lfs.attributes(DATA_DIR .. "/s2twp.json", "mode") ~= "file" then
        UIManager:show(InfoMessage:new{ text = _("OpenCC 尚未正確安裝在此裝置。") })
        return
    end

    local source = self.ui.document.file
    local extension = self:getCurrentFormat()
    local destination = output_path_for(source, extension)
    if lfs.attributes(destination) then
        UIManager:show(InfoMessage:new{
            text = _("繁體副本已存在：") .. "\n" .. display_name(destination),
        })
        return
    end

    UIManager:show(ConfirmBox:new{
        text = _("要建立這本書的台灣繁體副本嗎？原書會保留。\n\n")
            .. display_name(source),
        ok_text = _("轉換"),
        cancel_text = _("取消"),
        ok_callback = function()
            self:startConversion(source, destination, extension)
        end,
    })
end

function OpenCC:startConversion(source, destination, extension)
    local scratch_dir = PRIVATE_DIR .. "/run-" .. unique_suffix()
    if not lfs.mkdir(scratch_dir) then
        UIManager:show(InfoMessage:new{ text = _("無法建立 OpenCC 暫存檔。") })
        return
    end

    local progress = InfoMessage:new{ text = _("正在轉換為台灣繁體…") }
    UIManager:show(progress)
    UIManager:scheduleIn(0.1, function()
        local ok, result = pcall(function()
            if extension == "txt" then
                return convert_txt(source, destination, scratch_dir)
            end
            Epub.convert(source, destination, Android.dir, function(text, index)
                return convert_utf8_text(text, scratch_dir, index)
            end)
            return destination
        end)
        UIManager:close(progress)
        BaseUtil.purgeDir(scratch_dir)
        if not ok then
            local message = tostring(result):gsub("[\r\n]+", " ")
            if #message > 320 then message = message:sub(1, 317) .. "..." end
            UIManager:show(InfoMessage:new{ text = _("轉換失敗：") .. "\n" .. message, timeout = 10 })
            return
        end
        UIManager:show(ConfirmBox:new{
            text = _("已建立繁體副本：") .. "\n" .. display_name(result) .. "\n\n" .. _("要現在開啟嗎？"),
            ok_text = _("開啟副本"),
            cancel_text = _("繼續閱讀"),
            ok_callback = function()
                self.ui:switchDocument(result)
            end,
        })
    end)
end

function OpenCC:addToMainMenu(menu_items)
    menu_items.opencc = {
        text = _("簡體轉台灣繁體"),
        sub_item_table = {
            {
                text = _("將目前的 EPUB／TXT 轉成台灣繁體副本"),
                enabled_func = function() return self:isActionEnabled() end,
                callback = function() self:convertCurrentBook() end,
            },
        },
    }
end

return OpenCC
