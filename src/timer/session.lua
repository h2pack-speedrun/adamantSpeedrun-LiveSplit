-- Category session: an attempt log, rule checks and session timers.
--
-- Every run started while a session is open becomes an attempt. Rules decide whether a finished
-- attempt counts; the session completes once `runs` attempts have counted. See
-- docs/CATEGORIES_DESIGN.md for the full model.

local deps = ...
local core = deps.core

local Session = {}
Session.__index = Session

---@class LiveSplitSessionSettings
---@field runs integer Counted attempts needed to complete the session.
---@field distinct string "none" or a key each counted attempt must add a new value of.
---@field same string "none" or a key every attempt must share with the first valid attempt.
---@field onDeath string "continue" logs the failure; "reset" ends the session as failed.
---@field allowed table<string, boolean>? Permitted values of the `distinct` key; others are invalid.

--- Attempt statuses: "active", "counted", "failed", "duplicate", "invalid", and "paused" for a
--- pause between attempts (its `pausedCs` is how long the session clocks were stopped).
---@param settings LiveSplitSessionSettings
function Session.new(settings)
    local rta = core.RtaTimer:new()
    return setmetatable({
        settings = settings,
        attempts = {},
        counted = {},
        countedTotal = 0,
        referenceKeys = nil,
        activeAttempt = nil,
        -- The pause row while paused, and the wall clock measuring it.
        pauseRow = nil,
        pauseClock = nil,
        outcome = nil,
        started = false,
        igtSeconds = 0,
        rta = rta,
        lrt = core.LrtTimer:new({ rtaTimer = rta }),
    }, Session)
end

function Session:hasStarted()
    return self.started
end

--- Started and not yet completed or failed.
function Session:isOpen()
    return self.started and self.outcome == nil
end

--- nil while open; "completed" or "failed" once ended.
function Session:getOutcome()
    return self.outcome
end

function Session:getAttempts()
    return self.attempts
end

function Session:getActiveAttempt()
    return self.activeAttempt
end

function Session:getCountedTotal()
    return self.countedTotal
end

--- Most recent finished attempt, or nil.
function Session:getLastFinishedAttempt()
    for index = #self.attempts, 1, -1 do
        local attempt = self.attempts[index]
        if attempt.finished then
            return attempt
        end
    end
    return nil
end

local function breaksSameRule(self, attemptKeys)
    local sameKey = self.settings.same
    if sameKey == "none" or self.referenceKeys == nil then
        return false
    end
    return attemptKeys[sameKey] ~= self.referenceKeys[sameKey]
end

-- A run whose distinct key cannot be read, or is not a permitted value, can never count.
local function breaksDistinctRule(self, attemptKeys)
    local distinctKey = self.settings.distinct
    if distinctKey == "none" then
        return false
    end
    local value = attemptKeys[distinctKey]
    if value == nil then
        return true
    end
    return self.settings.allowed ~= nil and self.settings.allowed[value] ~= true
end

-- Pauses ----------------------------------------------------------------------------------------

function Session:isPaused()
    return self.pauseRow ~= nil
end

--- A pause is allowed between attempts of an open, running session.
function Session:canPause()
    return self:isOpen() and self.activeAttempt == nil and not self.suspended and self.pauseRow == nil
end

local function enterPause(self, row)
    self.rta:stop()
    self.lrt:stop()
    self.pauseRow = row
    self.pauseClock = core.RtaTimer:new()
    self.pauseClock:start((row.pausedCs or 0) / 100)
end

--- Stops the session clocks between attempts and returns the pause row. A pause right after
--- another, with no attempt between them, continues that row. Returns nil when not allowed.
function Session:pause()
    if not self:canPause() then
        return nil
    end
    local row = self.attempts[#self.attempts]
    if row == nil or row.status ~= "paused" then
        row = {
            index = #self.attempts + 1,
            keys = {},
            status = "paused",
            finished = true,
            pausedCs = 0,
        }
        self.attempts[row.index] = row
    end
    row.sessionIgtCs = core.toCentiseconds(self.igtSeconds)
    row.sessionRtaCs = self:rtaCs()
    row.sessionLrtCs = self:lrtCs()
    enterPause(self, row)
    return row
end

--- Ends the pause, restarting the session clocks. Returns the pause row, or nil when not paused.
function Session:unpause()
    local row = self.pauseRow
    if row == nil then
        return nil
    end
    row.pausedCs = core.toCentiseconds(self.pauseClock:getTime())
    self.pauseRow = nil
    self.pauseClock = nil
    self.rta:start(self.rta:getTime())
    self.lrt:start(self.lrt:getLoadTime())
    return row
end

--- How long `row` has been paused, live for the pause in progress.
function Session:pausedCs(row)
    if row == self.pauseRow then
        return core.toCentiseconds(self.pauseClock:getTime())
    end
    return row.pausedCs or 0
end

--- Starts an attempt for the run with game ordinal `runOrdinal`. A still-unfinished attempt is
--- dropped first, as the previous run was abandoned without being finalized; a pause ends. Returns
--- nil when the session has ended.
function Session:startAttempt(attemptKeys, runOrdinal)
    if self.outcome ~= nil then
        return nil
    end
    self:unpause()
    if self.activeAttempt ~= nil then
        table.remove(self.attempts)
        self.activeAttempt = nil
    end
    if not self.started then
        self.started = true
        self.rta:start()
        self.lrt:start()
    end

    local attempt = {
        index = #self.attempts + 1,
        keys = attemptKeys,
        runOrdinal = runOrdinal,
        status = "active",
        finished = false,
    }
    if breaksDistinctRule(self, attemptKeys) or breaksSameRule(self, attemptKeys) then
        attempt.status = "invalid"
    elseif self.referenceKeys == nil then
        self.referenceKeys = attemptKeys
    end
    self.attempts[#self.attempts + 1] = attempt
    self.activeAttempt = attempt
    return attempt
end

local function countAttempt(self, attempt)
    local distinctKey = self.settings.distinct
    if distinctKey == "none" then
        self.countedTotal = self.countedTotal + 1
        return "counted"
    end
    local value = attempt.keys[distinctKey]
    if value == nil or self.counted[value] then
        return "duplicate"
    end
    self.counted[value] = true
    self.countedTotal = self.countedTotal + 1
    return "counted"
end

local function endSession(self, outcome)
    self.outcome = outcome
    self.rta:stop()
    self.lrt:stop()
end

--- Finishes the active attempt with its run result and in-game time. Returns the attempt, or nil
--- when no attempt is active.
function Session:finishAttempt(cleared, igtSeconds)
    local attempt = self.activeAttempt
    if attempt == nil then
        return nil
    end
    self.activeAttempt = nil
    self.igtSeconds = self.igtSeconds + igtSeconds
    attempt.finished = true
    attempt.igtCs = core.toCentiseconds(igtSeconds)
    attempt.sessionIgtCs = core.toCentiseconds(self.igtSeconds)
    attempt.sessionRtaCs = self:rtaCs()
    attempt.sessionLrtCs = self:lrtCs()
    attempt.countIndex = nil

    if attempt.status == "invalid" then
        return attempt
    end
    if not cleared then
        attempt.status = "failed"
        if self.settings.onDeath == "reset" then
            endSession(self, "failed")
        end
        return attempt
    end
    attempt.status = countAttempt(self, attempt)
    if attempt.status == "counted" then
        attempt.countIndex = self.countedTotal
    end
    if self.countedTotal >= self.settings.runs then
        endSession(self, "completed")
    end
    return attempt
end

function Session:processLoadEvent(isLoading)
    if self:isOpen() then
        self.lrt:processLoadEvent(isLoading)
        return true
    end
    return false
end

function Session:rtaCs()
    return core.toCentiseconds(self.rta:getTime())
end

function Session:lrtCs()
    return core.toCentiseconds(self.lrt:getTime())
end

--- Summed in-game time of every finished attempt, plus the active attempt's live time.
function Session:igtCs(activeIgtSeconds)
    local activeCs = self.activeAttempt ~= nil and core.toCentiseconds(activeIgtSeconds or 0) or 0
    return core.toCentiseconds(self.igtSeconds) + activeCs
end

-- Persistence --------------------------------------------------------------------------------

local KEY_NAMES = { "route", "weapon", "aspect" }

--- A restored open session waits, timers frozen, until play resumes after a restart.
function Session:isSuspended()
    return self.suspended == true
end

function Session:resume()
    if not self.suspended then
        return
    end
    self.suspended = false
    -- A session saved while paused comes back paused; time with the game closed is not counted.
    local last = self.attempts[#self.attempts]
    if self.resumePaused and self.outcome == nil and last ~= nil and last.status == "paused" then
        self.resumePaused = nil
        enterPause(self, last)
        return
    end
    self.resumePaused = nil
    if self.outcome == nil then
        self.rta:start(self.rta:getTime())
        self.lrt:start(self.lrt:getLoadTime())
    end
end

--- Plain data describing the session, for saving. Times are centiseconds.
function Session:toRecord()
    local attempts = {}
    for index, attempt in ipairs(self.attempts) do
        local row = {
            status = attempt.status,
            runOrdinal = attempt.runOrdinal,
            igtCs = attempt.igtCs,
            sessionIgtCs = attempt.sessionIgtCs,
            sessionRtaCs = attempt.sessionRtaCs,
            sessionLrtCs = attempt.sessionLrtCs,
            countIndex = attempt.countIndex,
            pausedCs = attempt.status == "paused" and self:pausedCs(attempt) or nil,
            biomes = attempt.biomes,
        }
        for _, keyName in ipairs(KEY_NAMES) do
            row[keyName] = attempt.keys[keyName]
        end
        attempts[index] = row
    end
    return {
        state = self.outcome or (self.started and "open" or "new"),
        paused = self.pauseRow ~= nil,
        rtaCs = self:rtaCs(),
        loadCs = core.toCentiseconds(self.lrt:getLoadTime()),
        igtCs = core.toCentiseconds(self.igtSeconds),
        attempts = attempts,
    }
end

--- Rebuilds a session saved with `toRecord`. An open session comes back suspended.
---@param settings LiveSplitSessionSettings
function Session.restore(settings, record)
    local session = Session.new(settings)
    session.igtSeconds = (record.igtCs or 0) / 100
    session.rta.ElapsedTime = (record.rtaCs or 0) / 100
    session.lrt.LoadTime = (record.loadCs or 0) / 100

    for index, row in ipairs(record.attempts or {}) do
        local attemptKeys = {}
        for _, keyName in ipairs(KEY_NAMES) do
            attemptKeys[keyName] = row[keyName]
        end
        local attempt = {
            index = index,
            keys = attemptKeys,
            runOrdinal = row.runOrdinal,
            status = row.status,
            finished = row.status ~= "active",
            igtCs = row.igtCs,
            sessionIgtCs = row.sessionIgtCs,
            sessionRtaCs = row.sessionRtaCs,
            sessionLrtCs = row.sessionLrtCs,
            countIndex = row.countIndex,
            pausedCs = row.pausedCs,
            biomes = row.biomes or {},
        }
        session.attempts[index] = attempt
        if attempt.status ~= "invalid" and attempt.status ~= "paused" and session.referenceKeys == nil then
            session.referenceKeys = attemptKeys
        end
        if attempt.status == "counted" then
            session.countedTotal = session.countedTotal + 1
            if settings.distinct ~= "none" and attemptKeys[settings.distinct] ~= nil then
                session.counted[attemptKeys[settings.distinct]] = true
            end
        elseif attempt.status == "active" then
            session.activeAttempt = attempt
        end
    end

    if record.state == "completed" or record.state == "failed" then
        session.started = true
        session.outcome = record.state
    elseif record.state == "open" then
        session.started = true
        session.suspended = true
        session.resumePaused = record.paused == true
    end
    return session
end

return Session
