local progress = {}
local buffer = {}

local function get_terminal_size()
    local handle = io.popen("stty size 2>/dev/null || echo 24 80")
    local rows, cols = handle:read("*n", "*n")
    handle:close()
    return rows or 24, cols or 80
end

local function add_line(line, max_lines)
    table.insert(buffer, line)
    if #buffer > max_lines then
        table.remove(buffer, 1)
    end
end

local function render(progress_text)
    local rows, cols = get_terminal_size()
    local max_lines = rows - 1

    io.write("\27[2J\27[1;1H")
    
    for i = math.max(1, #buffer - max_lines + 1), #buffer do
        local line = buffer[i]
        if #line > cols then
            line = line:sub(1, cols)
        end
        io.write(line .. "\n")
    end

    local available_lines = rows - #buffer
    if available_lines > 0 then
        for _ = 1, available_lines do
            io.write("\n")
        end
    end

    io.write(string.format("\27[%d;1H", rows))
    io.write("\27[0J")
    
    local progress_width = math.floor(cols * 0.6)
    local percent_pos = progress_text:match("(%d+)%%")
    if percent_pos then
        local percent = tonumber(percent_pos)
        local filled = math.floor(progress_width * percent / 100)
        local bar = "[" .. string.rep("=", filled) .. string.rep(" ", progress_width - filled) .. "]"
        progress_text = progress_text:gsub("(%d+)%%", percent .. "%% " .. bar)
    end
    
    if #progress_text < cols then
        io.write("\27[7m" .. progress_text .. string.rep(" ", cols - #progress_text) .. "\27[0m")
    else
        io.write("\27[7m" .. progress_text:sub(1, cols) .. "\27[0m")
    end
    io.flush()
end

function progress.start_operation(operation_name)
    buffer = {}
    add_line("Starting " .. operation_name, get_terminal_size() - 1)
    render("Initializing...")
end

function progress.update_status(message)
    add_line(message, get_terminal_size() - 1)
    render(message)
end

function progress.update_progress(current, total, operation)
    local percent = total > 0 and math.floor((current / total) * 100) or 0
    local message = string.format("%s [%d/%d] %d%%", operation, current, total, percent)
    render(message)
end

function progress.finish_operation(success, final_message)
    local rows, cols = get_terminal_size()
    local message = success and "✓ " .. final_message or "✗ " .. final_message
    render(message)
    
    os.execute("sleep 0.5")
    io.write("\27[2J\27[1;1H")
    
    for _, line in ipairs(buffer) do
        if #line <= cols then
            io.write(line .. "\n")
        else
            io.write(line:sub(1, cols) .. "\n")
        end
    end
    
    io.write(message .. "\n")
    io.flush()
    buffer = {}
end

function progress.cleanup()
    io.write("\27[2J\27[1;1H")
    io.flush()
end

return progress