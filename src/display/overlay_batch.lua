local deps = ...
local batch = deps.batch
local overlay = deps.overlay
local isVisible = deps.isVisible
local isModeVisible = deps.isModeVisible
local formatCache = deps.formatCache
local maxBatchRunRows = deps.maxRows

local batchOverlay = {}
local projectionRows = {}
local projectionRunRows = {}
local projectionCurrentRow = { key = "current", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

for index = 1, maxBatchRunRows do
    projectionRunRows[index] = { key = "run" .. index, label = "", igt = "", rta = "", lrt = "" }
end

local function batchVisible(_, runtime)
    return isVisible(runtime) == true and batch.hasSession() == true
end

local function formatTime(row, mode, value, runtime)
    if value == nil or isModeVisible(mode, runtime) ~= true then
        return formatCache.cell(row, mode, nil)
    end
    return formatCache.cell(row, mode, value)
end

local function appendProjectionRow(source, projection, runtime)
    if source == nil then
        return
    end
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

function batchOverlay.register(overlays, order)
    overlays.createTable("batch", {
        componentName = "LiveSplit_Batch",
        region = overlay.region,
        order = order,
        maxRows = maxBatchRunRows + 1,
        columnGap = overlay.timerTableColumnGap,
        columns = overlay.buildTimerTableColumns(isModeVisible),
        visible = batchVisible,
    })
end

function batchOverlay.buildRows(runtime)
    local previousCount = projectionCount
    projectionCount = 0
    if not batchVisible(nil, runtime) then
        trimProjectionRows(previousCount)
        return projectionRows
    end

    local rows = batch.session()
    for index = 1, maxBatchRunRows do
        appendProjectionRow(rows.runs[index], projectionRunRows[index], runtime)
    end
    appendProjectionRow(rows.current, projectionCurrentRow, runtime)
    trimProjectionRows(previousCount)
    return projectionRows
end

function batchOverlay.project(ctx, runtime)
    ctx.setTable("batch", batchOverlay.buildRows(runtime))
end

return batchOverlay
