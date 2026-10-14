local deps = ...
local formatCentiseconds = deps.formatCentiseconds

local formatCache = {}

function formatCache.cell(row, mode, value)
    local csKey = mode .. "Cs"
    if value == nil then
        if row[csKey] ~= nil or row[mode] ~= "" then
            row[csKey] = nil
            row[mode] = ""
        end
        return row[mode]
    end

    if row[csKey] ~= value then
        row[csKey] = value
        row[mode] = formatCentiseconds(value)
    end
    return row[mode]
end

return formatCache
