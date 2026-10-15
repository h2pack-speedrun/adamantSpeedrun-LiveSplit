-- Multi-run session table: a title row (category, progress, page), the column headers, one page
-- of finished attempts, the current attempt with its biome splits, and the session total. The
-- title has a row of its own, with empty time cells, so a long title runs over blank space
-- instead of into the column headers.
--
-- In categories that keep splits, each attempt shows its biome rows with session times and a page
-- holds whole attempts. Otherwise the current attempt shows the live run's splits.

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
local currentRunDetails = deps.currentRunDetails

local batchOverlay = {}
local projectionRows = {}
local projectionPageRows = {}
local projectionCurrentRows = {}
local projectionTitleRow = { key = "title", label = "", igt = "", rta = "", lrt = "" }
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
    projectionTitleRow.label = headerLabel(rows, page, pages)
    appendRow(projectionTitleRow)
    projectionHeaderRow.label = ""
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

-- The current attempt: its heading, then its biome rows. Without kept splits the biomes come from
-- the live run's splits; the biome in progress already shows the run time, so the heading has none.
local function appendCurrent(rows, runtime, liveOnly)
    local heading = rows.current.heading
    if heading.label == nil or heading.label == "" then
        return
    end
    appendProjectionRow(heading, projectionCurrentRows[1], runtime)
    if rows.splits then
        for biome = 1, rows.current.biomeCount do
            appendProjectionRow(rows.current.biomes[biome], projectionCurrentRows[biome + 1], runtime)
        end
        return
    end
    local details = currentRunDetails(liveOnly)
    for biome = 1, maxBiomes do
        appendProjectionRow(details.biomes[biome], projectionCurrentRows[biome + 1], runtime)
    end
end

function batchOverlay.register(overlays, order)
    overlays.createTable("batch", {
        componentName = "LiveSplit_Batch",
        region = overlay.region,
        order = order,
        -- Title, column headers, one page of attempts, the current attempt with its biomes, session total.
        maxRows = maxPageSize + maxBiomes + 4,
        columnGap = overlay.timerTableColumnGap,
        -- Attempt labels ("Staff Circe (repeat)", "Current: Axe") need a wider label column.
        columns = overlay.buildTimerTableColumns(isModeVisible, overlay.sessionTableLabelWidth),
        visible = batchVisible,
    })
end

function batchOverlay.buildRows(runtime, liveOnly)
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
    appendCurrent(rows, runtime, liveOnly)
    appendProjectionRow(rows.total, projectionTotalRow, runtime)
    trimProjectionRows(previousCount)
    return projectionRows
end

function batchOverlay.project(ctx, runtime, liveOnly)
    ctx.setTable("batch", batchOverlay.buildRows(runtime, liveOnly))
end

return batchOverlay
