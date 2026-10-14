-- Multi-run session table: a pinned header, one page of finished attempts, the current attempt
-- and the session total. In categories that keep splits, each attempt shows its biome rows and a
-- page holds whole attempts.

local deps = ...
local batch = deps.batch
local overlay = deps.overlay
local isVisible = deps.isVisible
local isModeVisible = deps.isModeVisible
local formatCache = deps.formatCache
local paging = deps.paging
local readPageSize = deps.readPageSize
local maxPageSize = deps.maxPageSize
local maxBiomes = deps.maxBiomes

local batchOverlay = {}
local projectionRows = {}
local projectionPageRows = {}
local projectionCurrentRows = {}
local projectionHeaderRow = { key = "header", label = "", igt = "", rta = "", lrt = "" }
local projectionTotalRow = { key = "total", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

local function newProjection(key)
    return { key = key, label = "", igt = "", rta = "", lrt = "" }
end

for index = 1, maxPageSize do
    projectionPageRows[index] = newProjection("page" .. index)
end
projectionCurrentRows[1] = newProjection("current")
for index = 1, maxBiomes do
    projectionCurrentRows[index + 1] = newProjection("current" .. index)
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
    local label = ("%s %d/%d"):format(rows.title, rows.completedRuns, rows.targetRuns)
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
        -- Header, one page of attempts, the current attempt with its biomes, total.
        maxRows = maxPageSize + maxBiomes + 3,
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
    local pageRows = math.min(readPageSize(runtime), maxPageSize)
    -- With splits, an attempt takes a heading row plus its biome rows.
    local attemptsPerPage = rows.splits and math.max(1, math.floor(pageRows / (maxBiomes + 1))) or pageRows
    local first, last, page, pages = paging.view(rows.finishedCount, attemptsPerPage)
    appendHeader(rows, page, pages, runtime)
    local slot = 0
    for index = first, last do
        local group = rows.groups[index]
        slot = slot + 1
        appendProjectionRow(group.heading, projectionPageRows[slot], runtime)
        for biome = 1, group.biomeCount do
            if slot >= maxPageSize then
                break
            end
            slot = slot + 1
            appendProjectionRow(group.biomes[biome], projectionPageRows[slot], runtime)
        end
    end
    appendProjectionRow(rows.current.heading, projectionCurrentRows[1], runtime)
    for biome = 1, rows.current.biomeCount do
        appendProjectionRow(rows.current.biomes[biome], projectionCurrentRows[biome + 1], runtime)
    end
    appendProjectionRow(rows.total, projectionTotalRow, runtime)
    trimProjectionRows(previousCount)
    return projectionRows
end

function batchOverlay.project(ctx, runtime)
    ctx.setTable("batch", batchOverlay.buildRows(runtime))
end

return batchOverlay
