local M = {}

local function push(parts, value, visible)
    if value == "" then return end
    local last = parts[#parts]
    if last and last.visible == visible then
        last.value = last.value .. value
    else
        parts[#parts + 1] = { value = value, visible = visible }
    end
end

local function find_tag_end(text, start, declaration)
    local quote
    local bracket_depth = 0
    for index = start + 1, #text do
        local byte = text:byte(index)
        if quote then
            if byte == quote then quote = nil end
        elseif byte == 34 or byte == 39 then
            quote = byte
        elseif declaration and byte == 91 then
            bracket_depth = bracket_depth + 1
        elseif declaration and byte == 93 and bracket_depth > 0 then
            bracket_depth = bracket_depth - 1
        elseif byte == 62 and bracket_depth == 0 then
            return index + 1
        end
    end
    return #text + 1
end

local function is_ascii_letter(byte)
    return byte and ((byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122))
end

local function segments(text)
    local parts = {}
    local position = 1
    local raw_tag
    local lower = text:lower()

    while position <= #text do
        if raw_tag then
            local close_start = lower:find("</" .. raw_tag, position, true)
            while close_start do
                local next_byte = lower:byte(close_start + #raw_tag + 2)
                if next_byte == 62 or next_byte == 32 or next_byte == 9 or next_byte == 10 or next_byte == 13 then
                    break
                end
                close_start = lower:find("</" .. raw_tag, close_start + 2, true)
            end
            if not close_start then
                push(parts, text:sub(position), false)
                break
            end
            local close_end = find_tag_end(text, close_start, false)
            push(parts, text:sub(position, close_start - 1), false)
            push(parts, text:sub(close_start, close_end - 1), false)
            position = close_end
            raw_tag = nil
        else
            local opening = text:find("<", position, true)
            if not opening then
                push(parts, text:sub(position), true)
                break
            end
            if opening > position then
                push(parts, text:sub(position, opening - 1), true)
                position = opening
            end

            if text:sub(position, position + 3) == "<!--" then
                local close_end = text:find("-->", position + 4, true)
                close_end = close_end and close_end + 3 or (#text + 1)
                push(parts, text:sub(position, close_end - 1), false)
                position = close_end
            elseif text:sub(position, position + 8) == "<![CDATA[" then
                local close_end = text:find("]]>", position + 9, true)
                close_end = close_end and close_end + 3 or (#text + 1)
                push(parts, text:sub(position, close_end - 1), false)
                position = close_end
            elseif text:sub(position, position + 1) == "<?" then
                local close_end = text:find("?>", position + 2, true)
                close_end = close_end and close_end + 2 or (#text + 1)
                push(parts, text:sub(position, close_end - 1), false)
                position = close_end
            else
                local next_byte = text:byte(position + 1)
                if next_byte and not is_ascii_letter(next_byte) and next_byte ~= 47 and next_byte ~= 33 then
                    push(parts, "<", true)
                    position = position + 1
                else
                    local declaration = text:sub(position, position + 1) == "<!"
                    local close_end = find_tag_end(text, position, declaration)
                    if close_end > #text then
                        push(parts, text:sub(position), false)
                        break
                    end
                    local token = text:sub(position, close_end - 1)
                    push(parts, token, false)
                    position = close_end

                    local tag_name = token:match("^<%s*([%a][%w:%-]*)")
                    local closing = token:sub(1, 2) == "</"
                    local self_closing = token:match("/%s*>$") ~= nil
                    if tag_name and not closing and not self_closing then
                        tag_name = tag_name:lower()
                        if tag_name == "script" or tag_name == "style" then
                            raw_tag = tag_name
                        end
                    end
                end
            end
        end
    end
    return parts
end

local function utf8(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    elseif codepoint <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + math.floor(codepoint / 0x1000) % 0x40,
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end
    return nil
end

local function decode_cjk_entities(text)
    local function decode(value, base)
        local codepoint = tonumber(value, base)
        if codepoint and (
            (codepoint >= 0x3400 and codepoint <= 0x4DBF)
            or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
            or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
            or (codepoint >= 0x20000 and codepoint <= 0x3134F)
        ) then
            return utf8(codepoint)
        end
    end

    text = text:gsub("&#[xX]([%da-fA-F]+);", function(value)
        return decode(value, 16) or "&#x" .. value .. ";"
    end)
    return text:gsub("&#(%d+);", function(value)
        return decode(value, 10) or "&#" .. value .. ";"
    end)
end

local function make_marker(text)
    local seed = tostring(os.time()) .. tostring(math.random(100000, 999999))
    local marker = "__Z9_OC_BOUNDARY_" .. seed .. "__"
    while text:find(marker, 1, true) do
        seed = seed .. "x"
        marker = "__Z9_OC_BOUNDARY_" .. seed .. "__"
    end
    return marker
end

local function split_literal(text, delimiter)
    local result = {}
    local position = 1
    while true do
        local start_at, end_at = text:find(delimiter, position, true)
        if not start_at then
            result[#result + 1] = text:sub(position)
            break
        end
        result[#result + 1] = text:sub(position, start_at - 1)
        position = end_at + 1
    end
    return result
end

function M.convert(text, convert_text)
    local parts = segments(text)
    local visible = {}
    local indices = {}
    for index, part in ipairs(parts) do
        if part.visible and part.value ~= "" then
            visible[#visible + 1] = decode_cjk_entities(part.value)
            indices[#indices + 1] = index
        end
    end
    if #visible == 0 then return text, false end

    local marker = make_marker(text)
    local input = marker .. table.concat(visible, marker) .. marker
    local output = convert_text(input)
    local pieces = split_literal(output, marker)
    if #pieces ~= #visible + 2 or pieces[1] ~= "" or pieces[#pieces] ~= "" then
        error("OpenCC output boundary check failed")
    end

    local changed = false
    for index, part_index in ipairs(indices) do
        if pieces[index + 1] ~= parts[part_index].value then changed = true end
        parts[part_index].value = pieces[index + 1]
    end

    local output_parts = {}
    for _, part in ipairs(parts) do
        output_parts[#output_parts + 1] = part.value
    end
    return table.concat(output_parts), changed
end

return M
