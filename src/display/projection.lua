local deps = ...
local timer = deps.timer
local formatCache = deps.formatCache

local projection = {}
local projectedSummary = nil
local projectedSession = nil

function projection.begin()
    projectedSummary = nil
    projectedSession = nil
end

function projection.currentRunSummary()
    projectedSummary = projectedSummary or timer.currentRun.summary()
    return projectedSummary
end

function projection.batchSession()
    projectedSession = projectedSession or timer.batch.session()
    return projectedSession
end

function projection.displayTime(row, mode)
    local session = projection.batchSession()
    local batchTime = session.currentTime and session.currentTime[mode .. "Cs"]
    if session.hasSession == true and batchTime ~= nil then
        return formatCache.cell(row, "time", batchTime)
    end
    local timerSnapshot = projection.currentRunSummary()
    return formatCache.cell(row, "time", timerSnapshot[mode .. "Cs"])
end

return projection
