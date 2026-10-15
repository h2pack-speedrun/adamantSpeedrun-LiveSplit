local deps = ...
local currentRun = deps.currentRun
local overlay = deps.overlay
local isVisible = deps.isVisible
local isModeVisible = deps.isModeVisible
local formatCache = deps.formatCache

local splitOverlay = {}
local projectionRows = {}
local projectionHeaderRow = { key = "header", label = "", igt = "", rta = "", lrt = "" }
local projectionBiomeRows = {
    { key = "biome1", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome2", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome3", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome4", label = "", igt = "", rta = "", lrt = "" },
}
local projectionTotalRow = { key = "total", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

local function splitVisible(_, runtime)
    return isVisible(runtime) == true and currentRun.hasDetails() == true
end

local function formatTime(row, mode, value, runtime)
    if value == nil or isModeVisible(mode, runtime) ~= true then
        return formatCache.cell(row, mode, nil)
    end
    return formatCache.cell(row, mode, value)
end

local function appendProjectionRow(source, projection, runtime)
    if source.label == nil or source.label == "" then
        return
    end

    projection.label = source.label
    formatTime(projection, "igt", source.igtCs, runtime)
    formatTime(projection, "rta", source.rtaCs, runtime)
    formatTime(projection, "lrt", source.lrtCs, runtime)

    projectionCount = projectionCount + 1
    projectionRows[projectionCount] = projection
end

local function trimProjectionRows(previousCount)
    for index = projectionCount + 1, previousCount do
        projectionRows[index] = nil
    end
end

function splitOverlay.register(overlays, order)
    overlays.createTable("splits", {
        componentName = "LiveSplit_Split",
        region = overlay.region,
        order = order,
        hudVisibility = overlay.hudVisibility,
        maxRows = 6,
        columnGap = overlay.timerTableColumnGap,
        columns = overlay.buildTimerTableColumns(isModeVisible),
        visible = splitVisible,
    })
end

function splitOverlay.buildRows(runtime, liveOnly)
    local previousCount = projectionCount
    projectionCount = 0
    if not splitVisible(nil, runtime) then
        trimProjectionRows(previousCount)
        return projectionRows
    end

    local rows = currentRun.detailsSnapshot(liveOnly)

    projectionHeaderRow.label = "Biome"
    projectionHeaderRow.igt = isModeVisible("igt", runtime) and "IGT" or ""
    projectionHeaderRow.rta = isModeVisible("rta", runtime) and "RTA" or ""
    projectionHeaderRow.lrt = isModeVisible("lrt", runtime) and "LrT" or ""
    projectionCount = projectionCount + 1
    projectionRows[projectionCount] = projectionHeaderRow
    for index = 1, 4 do
        appendProjectionRow(rows.biomes[index], projectionBiomeRows[index], runtime)
    end
    appendProjectionRow(rows.total, projectionTotalRow, runtime)
    trimProjectionRows(previousCount)
    return projectionRows
end

function splitOverlay.project(ctx, runtime, liveOnly)
    ctx.setTable("splits", splitOverlay.buildRows(runtime, liveOnly))
end

return splitOverlay
