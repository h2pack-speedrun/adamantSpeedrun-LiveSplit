-- Multi-run session table: a pinned header, one page of finished attempts, the current attempt
-- and the session total.

local deps = ...
local batch = deps.batch
local overlay = deps.overlay
local isVisible = deps.isVisible
local isModeVisible = deps.isModeVisible
local formatCache = deps.formatCache
local paging = deps.paging
local readPageSize = deps.readPageSize
local maxPageSize = deps.maxPageSize

local batchOverlay = {}
local projectionRows = {}
local projectionPageRows = {}
local projectionHeaderRow = { key = "header", label = "", igt = "", rta = "", lrt = "" }
local projectionCurrentRow = { key = "current", label = "", igt = "", rta = "", lrt = "" }
local projectionTotalRow = { key = "total", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

for index = 1, maxPageSize do
    projectionPageRows[index] = { key = "page" .. index, label = "", igt = "", rta = "", lrt = "" }
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

local function appendRow(projection)
    projectionCount = projectionCount + 1
    projectionRows[projectionCount] = projection
end

local function appendProjectionRow(source, projection, runtime)
    if source == nil or source.label == nil or source.label == "" then
        return
    end
    projection.label = source.label
    formatTime(projection, "igt", source.igtCs, runtime)
    formatTime(projection, "rta", source.rtaCs, runtime)
    formatTime(projection, "lrt", source.lrtCs, runtime)
    appendRow(projection)
end

local function headerLabel(rows, page, pages)
    local label = ("Runs %d/%d"):format(rows.completedRuns, rows.targetRuns)
    if rows.failedCount > 0 then
        label = label .. (" · %d failed"):format(rows.failedCount)
    end
    if pages > 1 then
        label = label .. (" · p%d/%d"):format(page, pages)
    end
    return label
end

local function appendHeader(rows, page, pages, runtime)
    projectionHeaderRow.label = headerLabel(rows, page, pages)
    projectionHeaderRow.igt = isModeVisible("igt", runtime) and "IGT" or ""
    projectionHeaderRow.rta = isModeVisible("rta", runtime) and "RTA" or ""
    projectionHeaderRow.lrt = isModeVisible("lrt", runtime) and "LrT" or ""
    appendRow(projectionHeaderRow)
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
        -- Header, one page of attempts, current attempt, total.
        maxRows = maxPageSize + 3,
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
    local pageSize = math.min(readPageSize(runtime), maxPageSize)
    local first, last, page, pages = paging.view(rows.finishedCount, pageSize)
    appendHeader(rows, page, pages, runtime)
    for index = first, last do
        appendProjectionRow(rows.runs[index], projectionPageRows[index - first + 1], runtime)
    end
    appendProjectionRow(rows.current, projectionCurrentRow, runtime)
    appendProjectionRow(rows.total, projectionTotalRow, runtime)
    trimProjectionRows(previousCount)
    return projectionRows
end

function batchOverlay.project(ctx, runtime)
    ctx.setTable("batch", batchOverlay.buildRows(runtime))
end

return batchOverlay
