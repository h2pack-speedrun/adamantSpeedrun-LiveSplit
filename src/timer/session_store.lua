-- Saves a multi-run session record into persisted module status and reads it back.
--
-- Every persisted status write rewrites the module config file, so writes stay incremental:
-- checkpoints touch the session clocks only, and attempt changes touch one table row.

local store = {}

local ATTEMPTS = "SessionAttempts"
-- The config file is user-editable, so only known session states load.
local SAVED_STATES = {
    open = true,
    completed = true,
    failed = true,
}
local KEY_COLUMNS = {
    route = "Route",
    weapon = "Weapon",
    aspect = "Aspect",
}

local function emptyToNil(value)
    if value == "" then
        return nil
    end
    return value
end

local function zeroToNil(value)
    if value == 0 then
        return nil
    end
    return value
end

local function toRow(attempt)
    local row = {
        Status = attempt.status,
        RunOrdinal = attempt.runOrdinal or -1,
        IgtCs = attempt.igtCs or 0,
        SessionIgtCs = attempt.sessionIgtCs or 0,
        SessionRtaCs = attempt.sessionRtaCs or 0,
        SessionLrtCs = attempt.sessionLrtCs or 0,
        CountIndex = attempt.countIndex or 0,
    }
    for keyName, column in pairs(KEY_COLUMNS) do
        row[column] = attempt[keyName] or ""
    end
    return row
end

local function fromRow(row)
    local attempt = {
        status = row.Status,
        runOrdinal = row.RunOrdinal >= 0 and row.RunOrdinal or nil,
        igtCs = row.IgtCs,
        sessionIgtCs = row.SessionIgtCs,
        sessionRtaCs = row.SessionRtaCs,
        sessionLrtCs = row.SessionLrtCs,
        countIndex = zeroToNil(row.CountIndex),
    }
    for keyName, column in pairs(KEY_COLUMNS) do
        attempt[keyName] = emptyToNil(row[column])
    end
    return attempt
end

--- Session clocks: called at game checkpoints and whenever totals change.
function store.saveClocks(status, record)
    status.write("SessionRtaCs", record.rtaCs)
    status.write("SessionLoadCs", record.loadCs)
end

--- Session state, run target, clocks and summed IGT.
function store.saveTotals(status, record, runs)
    status.write("SessionState", record.state)
    status.write("SessionRuns", runs)
    store.saveClocks(status, record)
    status.write("SessionIgtCs", record.igtCs)
end

--- Saves attempt `index` from the record, appending it or replacing the stored row.
--- Returns false once the stored attempt log is full.
function store.saveAttempt(status, record, index)
    local attempts = status.get(ATTEMPTS)
    local row = toRow(record.attempts[index])
    local count = attempts:count()
    if index <= count then
        attempts:remove(index)
        return attempts:insert(index, row)
    end
    return attempts:append(row)
end

function store.clear(status)
    status.write("SessionState", "")
    status.write("SessionRuns", 0)
    status.write("SessionRtaCs", 0)
    status.write("SessionLoadCs", 0)
    status.write("SessionIgtCs", 0)
    status.get(ATTEMPTS):clear()
end

--- The saved session record and its run target, or nil when nothing is saved.
function store.load(status)
    local state = status.read("SessionState")
    if not SAVED_STATES[state] then
        return nil
    end
    local attempts = {}
    for index, row in ipairs(status.get(ATTEMPTS):snapshots()) do
        attempts[index] = fromRow(row)
    end
    return {
        state = state,
        rtaCs = status.read("SessionRtaCs"),
        loadCs = status.read("SessionLoadCs"),
        igtCs = status.read("SessionIgtCs"),
        attempts = attempts,
    }, status.read("SessionRuns")
end

return store
