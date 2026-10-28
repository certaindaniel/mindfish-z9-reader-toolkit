local M = {}

local bit = require("bit")
local lfs = require("libs/libkoreader-lfs")
local ZipWriter = require("opencc_zipwriter")
local Markup = require("opencc_markup")
local BaseUtil = require("ffi/util")

local MAX_ENTRIES = 20000
local MAX_CENTRAL_DIRECTORY = 16 * 1024 * 1024
local MAX_ENTRY_SIZE = 64 * 1024 * 1024
local MAX_TOTAL_SIZE = 512 * 1024 * 1024
local MAX_ARCHIVE_SIZE = 1024 * 1024 * 1024
local MAX_TEXT_SIZE = 32 * 1024 * 1024
local MIMETYPE = "application/epub+zip"

local function fail(message)
    error(message, 0)
end

local function le(data, position, width)
    if position < 1 or position + width - 1 > #data then
        fail("Unexpected end of ZIP data")
    end
    local value = 0
    local multiplier = 1
    for index = 0, width - 1 do
        value = value + data:byte(position + index) * multiplier
        multiplier = multiplier * 256
    end
    return value
end

local function read_at(file, offset, length)
    if offset < 0 or length < 0 then fail("Invalid ZIP offset") end
    local seek_result = file:seek("set", offset)
    if not seek_result then fail("Unable to seek in EPUB") end
    local data = file:read(length)
    if not data or #data ~= length then fail("Truncated EPUB archive") end
    return data
end

local function valid_utf8(value)
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        if first < 0x80 then
            index = index + 1
        elseif first >= 0xC2 and first <= 0xDF then
            local second = value:byte(index + 1)
            if not second or second < 0x80 or second > 0xBF then return false end
            index = index + 2
        elseif first == 0xE0 then
            local second, third = value:byte(index + 1, index + 2)
            if not second or not third or second < 0xA0 or second > 0xBF
                    or third < 0x80 or third > 0xBF then return false end
            index = index + 3
        elseif (first >= 0xE1 and first <= 0xEC) or (first >= 0xEE and first <= 0xEF) then
            local second, third = value:byte(index + 1, index + 2)
            if not second or not third or second < 0x80 or second > 0xBF
                    or third < 0x80 or third > 0xBF then return false end
            index = index + 3
        elseif first == 0xED then
            local second, third = value:byte(index + 1, index + 2)
            if not second or not third or second < 0x80 or second > 0x9F
                    or third < 0x80 or third > 0xBF then return false end
            index = index + 3
        elseif first == 0xF0 then
            local second, third, fourth = value:byte(index + 1, index + 3)
            if not second or not third or not fourth or second < 0x90 or second > 0xBF
                    or third < 0x80 or third > 0xBF or fourth < 0x80 or fourth > 0xBF then return false end
            index = index + 4
        elseif first >= 0xF1 and first <= 0xF3 then
            local second, third, fourth = value:byte(index + 1, index + 3)
            if not second or not third or not fourth or second < 0x80 or second > 0xBF
                    or third < 0x80 or third > 0xBF or fourth < 0x80 or fourth > 0xBF then return false end
            index = index + 4
        elseif first == 0xF4 then
            local second, third, fourth = value:byte(index + 1, index + 3)
            if not second or not third or not fourth or second < 0x80 or second > 0x8F
                    or third < 0x80 or third > 0xBF or fourth < 0x80 or fourth > 0xBF then return false end
            index = index + 4
        else
            return false
        end
    end
    return true
end

M.isValidUtf8 = valid_utf8

local function validate_name(name, utf8_flag)
    if name == "" or name:sub(1, 1) == "/" or name:find("\\", 1, true)
            or name:find(":", 1, true) or name:find("//", 1, true) then
        fail("EPUB contains an unsafe ZIP path")
    end
    for index = 1, #name do
        local byte = name:byte(index)
        if byte < 32 or byte == 127 then fail("EPUB contains a control character in a ZIP path") end
        if not utf8_flag and byte >= 128 then
            fail("EPUB uses a non-UTF-8 filename that KOReader cannot safely rewrite")
        end
    end
    if utf8_flag and not valid_utf8(name) then fail("EPUB contains an invalid UTF-8 filename") end
    local normalized = name:sub(-1) == "/" and name:sub(1, -2) or name
    for segment in normalized:gmatch("[^/]+") do
        if segment == "." or segment == ".." then fail("EPUB contains a traversing ZIP path") end
    end
    if normalized == "" then fail("EPUB contains an invalid root path") end
end

local function archive_entries(path)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then fail("The current EPUB file cannot be read") end
    if attr.size > MAX_ARCHIVE_SIZE then fail("This EPUB is larger than the on-device converter supports") end

    local file, open_error = io.open(path, "rb")
    if not file then fail("Cannot open EPUB: " .. tostring(open_error)) end
    local ok, result = pcall(function()
        local tail_length = math.min(attr.size, 65557)
        local tail_offset = attr.size - tail_length
        local tail = read_at(file, tail_offset, tail_length)
        local eocd_position
        local search_from = 1
        while search_from >= 1 do
            local candidate = tail:find("PK\005\006", search_from, true)
            if not candidate then break end
            if candidate + 21 <= #tail then
                local comment_length = le(tail, candidate + 20, 2)
                if candidate + 22 + comment_length - 1 == #tail then
                    eocd_position = candidate
                end
            end
            if candidate >= #tail then
                break
            end
            search_from = candidate + 1
        end
        if not eocd_position then
            fail("EPUB has no valid ZIP end record")
        end

        local eocd_offset = tail_offset + eocd_position - 1
        local disk_number = le(tail, eocd_position + 4, 2)
        local central_disk = le(tail, eocd_position + 6, 2)
        local disk_entries = le(tail, eocd_position + 8, 2)
        local entry_count = le(tail, eocd_position + 10, 2)
        local central_size = le(tail, eocd_position + 12, 4)
        local central_offset = le(tail, eocd_position + 16, 4)
        if disk_number ~= 0 or central_disk ~= 0 or disk_entries ~= entry_count
                or entry_count == 0xFFFF or central_size == 0xFFFFFFFF
                or central_offset == 0xFFFFFFFF then
            fail("Multi-disk and ZIP64 EPUB files are not supported")
        end
        if entry_count == 0 or entry_count > MAX_ENTRIES then fail("EPUB has too many ZIP entries") end
        if central_size > MAX_CENTRAL_DIRECTORY or central_offset + central_size ~= eocd_offset then
            fail("EPUB has an unsupported ZIP directory layout")
        end

        local central = read_at(file, central_offset, central_size)
        local entries = {}
        local seen_names = {}
        local total_uncompressed = 0
        local position = 1
        for _ = 1, entry_count do
            if le(central, position, 4) ~= 0x02014B50 then fail("Invalid EPUB central directory entry") end
            local made_by = le(central, position + 4, 2)
            local flags = le(central, position + 8, 2)
            local method = le(central, position + 10, 2)
            local crc = le(central, position + 16, 4)
            local compressed_size = le(central, position + 20, 4)
            local uncompressed_size = le(central, position + 24, 4)
            local name_length = le(central, position + 28, 2)
            local extra_length = le(central, position + 30, 2)
            local comment_length = le(central, position + 32, 2)
            local start_disk = le(central, position + 34, 2)
            local external_attributes = le(central, position + 38, 4)
            local local_offset = le(central, position + 42, 4)
            local record_end = position + 46 + name_length + extra_length + comment_length
            if record_end - 1 > #central then fail("Truncated EPUB central directory entry") end
            if name_length == 0 or start_disk ~= 0 then fail("Unsupported EPUB ZIP entry") end
            if method ~= 0 and method ~= 8 then fail("EPUB uses an unsupported compression method") end
            if bit.band(flags, 0xF7F1) ~= 0 or (method == 0 and bit.band(flags, 0x0006) ~= 0) then
                fail("EPUB uses unsupported ZIP flags or encryption")
            end

            local is_utf8 = bit.band(flags, 0x0800) ~= 0
            local name = central:sub(position + 46, position + 45 + name_length)
            validate_name(name, is_utf8)
            if seen_names[name] then fail("EPUB contains duplicate ZIP paths") end
            seen_names[name] = true

            local is_directory = name:sub(-1) == "/"
            local unix_host = math.floor(made_by / 256) == 3
            local unix_mode = unix_host and bit.band(bit.rshift(external_attributes, 16), 0xFFFF) or 0
            local file_type = bit.band(unix_mode, 0xF000)
            if file_type ~= 0 and file_type ~= 0x8000 and file_type ~= 0x4000 then
                fail("EPUB contains a non-regular ZIP entry")
            end
            if (file_type == 0x4000 and not is_directory) or (file_type == 0x8000 and is_directory) then
                fail("EPUB ZIP entry path and file type disagree")
            end
            if is_directory and uncompressed_size ~= 0 then fail("EPUB contains a non-empty directory entry") end
            if uncompressed_size > MAX_ENTRY_SIZE then fail("EPUB has an entry too large for this reader") end
            total_uncompressed = total_uncompressed + uncompressed_size
            if total_uncompressed > MAX_TOTAL_SIZE then fail("EPUB expands beyond the on-device safety limit") end

            local local_header = read_at(file, local_offset, 30)
            if le(local_header, 1, 4) ~= 0x04034B50 then fail("Invalid EPUB local ZIP header") end
            local local_flags = le(local_header, 7, 2)
            local local_method = le(local_header, 9, 2)
            local local_crc = le(local_header, 15, 4)
            local local_compressed_size = le(local_header, 19, 4)
            local local_uncompressed_size = le(local_header, 23, 4)
            local local_name_length = le(local_header, 27, 2)
            local local_extra_length = le(local_header, 29, 2)
            if local_flags ~= flags or local_method ~= method or local_name_length ~= name_length then
                fail("EPUB central and local ZIP headers do not match")
            end
            local local_variable = read_at(file, local_offset + 30, local_name_length + local_extra_length)
            if local_variable:sub(1, local_name_length) ~= name then
                fail("EPUB central and local ZIP paths do not match")
            end
            if bit.band(flags, 0x0008) == 0
                    and (local_crc ~= crc or local_compressed_size ~= compressed_size
                        or local_uncompressed_size ~= uncompressed_size) then
                fail("EPUB ZIP sizes or checksums do not match")
            end
            local data_offset = local_offset + 30 + local_name_length + local_extra_length
            local data_end = data_offset + compressed_size
            if data_end > central_offset then fail("EPUB ZIP entry data overlaps its directory") end

            entries[#entries + 1] = {
                name = name,
                flags = flags,
                method = method,
                crc = crc,
                compressed_size = compressed_size,
                uncompressed_size = uncompressed_size,
                local_offset = local_offset,
                local_end = data_end,
                local_extra_length = local_extra_length,
                is_directory = is_directory,
            }
            position = record_end
        end
        if position ~= #central + 1 then fail("EPUB central directory has unexpected trailing data") end

        local intervals = {}
        for _, entry in ipairs(entries) do
            intervals[#intervals + 1] = { entry.local_offset, entry.local_end }
        end
        table.sort(intervals, function(left, right) return left[1] < right[1] end)
        for index = 2, #intervals do
            if intervals[index][1] < intervals[index - 1][2] then fail("EPUB ZIP entries overlap") end
        end

        if entries[1].name ~= "mimetype" or entries[1].local_offset ~= 0 or entries[1].method ~= 0
                or entries[1].uncompressed_size ~= #MIMETYPE or entries[1].local_extra_length ~= 0 then
            fail("EPUB does not follow the required mimetype ZIP layout")
        end
        return entries
    end)
    file:close()
    if not ok then error(result, 0) end
    return result
end

local function read_file(path, maximum)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then fail("EPUB entry was not extracted: " .. path) end
    if attr.size > maximum then fail("EPUB entry is too large to process") end
    local file, open_error = io.open(path, "rb")
    if not file then fail("Cannot read extracted EPUB entry: " .. tostring(open_error)) end
    local content = file:read("*a")
    file:close()
    if not content then fail("Could not read extracted EPUB entry") end
    return content
end

local function is_text_entry(name)
    local ext = name:match("%.([^./]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "xhtml" or ext == "html" or ext == "htm" or ext == "xml"
        or ext == "ncx" or ext == "opf" or ext == "svg"
end

local function is_already_compressed(name)
    local ext = name:match("%.([^./]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "gif"
        or ext == "webp" or ext == "avif" or ext == "mp3" or ext == "mp4"
        or ext == "m4a" or ext == "m4v" or ext == "aac" or ext == "ogg"
        or ext == "opus" or ext == "flac" or ext == "zip" or ext == "pdf"
        or ext == "woff" or ext == "woff2"
end

local function unique_suffix()
    return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function validate_output(path, expected, verify_dir)
    local entries = archive_entries(path)
    if #entries ~= #expected then fail("Generated EPUB has an unexpected ZIP entry count") end
    for index, entry in ipairs(entries) do
        local wanted = expected[index]
        if entry.name ~= wanted.name or entry.method ~= wanted.method
                or entry.crc ~= wanted.crc or entry.uncompressed_size ~= wanted.size then
            fail("Generated EPUB failed its ZIP read-back check")
        end
    end
    local status = BaseUtil.execute("/system/bin/busybox", "unzip", "-o", "-q", path, "-d", verify_dir)
    if status ~= 0 then fail("Generated EPUB could not be extracted for verification") end
    for index, entry in ipairs(entries) do
        local content = read_file(verify_dir .. "/" .. entry.name, MAX_ENTRY_SIZE)
        if #content ~= expected[index].size or ZipWriter.crc32(content) ~= expected[index].crc then
            fail("Generated EPUB failed its content read-back check")
        end
    end
end

function M.convert(source_path, output_path, private_dir, convert_text)
    if lfs.attributes(output_path) then fail("The Traditional Chinese copy already exists") end
    local entries = archive_entries(source_path)
    local suffix = unique_suffix()
    local work_dir = private_dir .. "/opencc-epub-" .. suffix
    local partial_path = output_path .. ".partial-" .. suffix
    if lfs.attributes(work_dir) or lfs.attributes(partial_path) then fail("Temporary conversion path already exists") end
    if not lfs.mkdir(work_dir) then fail("Cannot create a private EPUB work directory") end

    local writer
    local ok, result = pcall(function()
        local status = BaseUtil.execute("/system/bin/busybox", "unzip", "-o", "-q", source_path, "-d", work_dir)
        if status ~= 0 then fail("Android could not extract this EPUB") end

        local mimetype = read_file(work_dir .. "/mimetype", #MIMETYPE)
        if mimetype ~= MIMETYPE then fail("The EPUB mimetype entry is invalid") end
        local container_path = work_dir .. "/META-INF/container.xml"
        local container_attr = lfs.attributes(container_path)
        if not container_attr or container_attr.mode ~= "file" then fail("EPUB has no container.xml") end
        local has_opf = false
        for _, entry in ipairs(entries) do
            if not entry.is_directory and entry.name:lower():match("%.opf$") then has_opf = true end
        end
        if not has_opf then fail("EPUB package document was not found") end

        writer = ZipWriter:new()
        if not writer:open(partial_path) then fail("Cannot create the converted EPUB") end
        local expected = {}
        local text_index = 0
        local output_total = 0
        for _, entry in ipairs(entries) do
            if not entry.is_directory then
                local content = read_file(work_dir .. "/" .. entry.name, MAX_ENTRY_SIZE)
                if #content ~= entry.uncompressed_size or ZipWriter.crc32(content) ~= entry.crc then
                    fail("An EPUB entry failed its size or checksum check")
                end
                local method = is_already_compressed(entry.name) and 0 or 8
                if entry.name == "mimetype" then
                    if content ~= MIMETYPE then fail("The EPUB mimetype entry is invalid") end
                    method = 0
                elseif is_text_entry(entry.name) then
                    if #content > MAX_TEXT_SIZE then fail("An EPUB text document is too large to convert") end
                    if content:find("%z") or not valid_utf8(content) then
                        fail("EPUB text must use valid UTF-8 encoding")
                    end
                    local declared_encoding = content:match("[Ee]ncoding%s*=%s*['\"]([^'\"]+)")
                    if declared_encoding and declared_encoding:upper():gsub("_", "-") ~= "UTF-8" then
                        fail("EPUB text uses a non-UTF-8 XML encoding")
                    end
                    text_index = text_index + 1
                    content = Markup.convert(content, function(visible_text)
                        return convert_text(visible_text, text_index)
                    end)
                    method = 8
                end
                if #content > MAX_ENTRY_SIZE then fail("Converted EPUB entry is too large") end
                output_total = output_total + #content
                if output_total > MAX_TOTAL_SIZE then fail("Converted EPUB exceeds the on-device size limit") end
                writer:add(entry.name, content, method == 0)
                expected[#expected + 1] = {
                    name = entry.name,
                    method = method,
                    crc = ZipWriter.crc32(content),
                    size = #content,
                }
            end
        end
        if not writer:close() then fail("Could not finish the converted EPUB ZIP") end
        writer = nil
        if not BaseUtil.purgeDir(work_dir) then fail("Cannot prepare the EPUB read-back check") end
        if not lfs.mkdir(work_dir) then fail("Cannot prepare the EPUB read-back check") end
        validate_output(partial_path, expected, work_dir)
        if lfs.attributes(output_path) then fail("The Traditional Chinese copy already exists") end
        local renamed, rename_error = os.rename(partial_path, output_path)
        if not renamed then fail("Cannot publish the converted EPUB: " .. tostring(rename_error)) end
        return true
    end)

    if writer and writer.ziphandle then pcall(function() writer.ziphandle:close() end) end
    if lfs.attributes(partial_path) then os.remove(partial_path) end
    if lfs.attributes(work_dir) then BaseUtil.purgeDir(work_dir) end
    if not ok then error(result, 0) end
    return result
end

return M
