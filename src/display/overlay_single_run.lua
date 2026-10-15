local deps = ...
local overlay = deps.overlay
local isModeVisible = deps.isModeVisible
local isTimerDisplayVisible = deps.isTimerDisplayVisible
local getDisplayTime = deps.getDisplayTime

local singleRunOverlay = {}
local REGION = overlay.region
local LINES = {
    {
        name = "summary.igt",
        label = "IGT",
        mode = "igt",
        orderOffset = 0,
    },
    {
        name = "summary.rta",
        label = "RTA",
        mode = "rta",
        orderOffset = 1,
    },
    {
        name = "summary.lrt",
        label = "LrT",
        mode = "lrt",
        orderOffset = 2,
    },
}
local lineValues = {
    igt = { label = "IGT:", time = "" },
    rta = { label = "RTA:", time = "" },
    lrt = { label = "LrT:", time = "" },
}

local function isLineVisible(mode, runtime)
    return isTimerDisplayVisible(runtime) == true
        and isModeVisible(mode, runtime) == true
end

local function updateLine(mode, runtime)
    local line = lineValues[mode]
    if isLineVisible(mode, runtime) then
        getDisplayTime(line, mode)
    else
        line.time = ""
        line.timeCs = nil
    end
    return line
end

function singleRunOverlay.register(overlays, order)
    for _, line in ipairs(LINES) do
        overlays.createLine(line.name, {
            componentName = "LiveSplit_" .. line.label,
            region = REGION,
            order = order + line.orderOffset,
            columnGap = 20,
            columns = overlay.buildSummaryColumns(),
            visible = function(_, runtime)
                return isLineVisible(line.mode, runtime)
            end,
        })
    end
end

function singleRunOverlay.project(ctx, runtime)
    for _, line in ipairs(LINES) do
        ctx.setLine(line.name, updateLine(line.mode, runtime))
    end
end

return singleRunOverlay
