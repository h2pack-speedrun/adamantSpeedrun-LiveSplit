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
local MAX_BIOMES = 4
local KEY_COLUMNS = {
    route = "Route",
    weapon = "Weapon",
    aspect = "Aspect",
}

-- Allowed regions as a comma list: "underworld,surface"; "" when any region counts.
local function encodeAllowed(allowed)
    if allowed == nil then
        return ""
    end
    local values = {}
    for value, permitted in pairs(allowed) do
        if permitted == true then
            values[#values + 1] = value
        end
    end
    table.sort(values)
    return table.concat(values, ",")
end

local function decodeAllowed(text)
    if text == nil or text == "" then
        return nil
    end
    local allowed = {}
    for value in text:gmatch("[^,]+") do
        allowed[value] = true
    end
    return allowed
end

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
        PausedCs = attempt.pausedCs or 0,
    }
    for keyName, column in pairs(KEY_COLUMNS) do
        row[column] = attempt[keyName] or ""
    end
    for index = 1, MAX_BIOMES do
        local split = attempt.biomes and attempt.biomes[index]
        local prefix = "B" .. index
        row[prefix .. "Code"] = split and split.code or ""
        row[prefix .. "IgtCs"] = split and split.igtCs or 0
        row[prefix .. "RtaCs"] = split and split.rtaCs or 0
        row[prefix .. "LrtCs"] = split and split.lrtCs or 0
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
        pausedCs = row.Status == "paused" and row.PausedCs or nil,
    }
    for keyName, column in pairs(KEY_COLUMNS) do
        attempt[keyName] = emptyToNil(row[column])
    end
    local biomes = {}
    for index = 1, MAX_BIOMES do
        local prefix = "B" .. index
        local code = emptyToNil(row[prefix .. "Code"])
        if code ~= nil then
            biomes[#biomes + 1] = {
                code = code,
                igtCs = row[prefix .. "IgtCs"],
                rtaCs = row[prefix .. "RtaCs"],
                lrtCs = row[prefix .. "LrtCs"],
            }
        end
    end
    attempt.biomes = biomes
    return attempt
end

-- Each persisted status write rewrites the config file; skip writes that change nothing.
local function writeIfChanged(status, alias, value)
    if status.read(alias) ~= value then
        status.write(alias, value)
    end
end

--- Session clocks: called at game checkpoints and whenever totals change.
function store.saveClocks(status, record)
    writeIfChanged(status, "SessionRtaCs", record.rtaCs)
    writeIfChanged(status, "SessionLoadCs", record.loadCs)
end

--- Session state, rules, clocks and summed IGT.
function store.saveTotals(status, record, settings)
    writeIfChanged(status, "SessionState", record.state)
    writeIfChanged(status, "SessionPaused", record.paused == true)
    writeIfChanged(status, "SessionCategory", settings.category or "")
    writeIfChanged(status, "SessionDistinct", settings.distinct or "")
    writeIfChanged(status, "SessionSame", settings.same or "")
    writeIfChanged(status, "SessionOnDeath", settings.onDeath or "")
    writeIfChanged(status, "SessionAllowed", encodeAllowed(settings.allowed))
    writeIfChanged(status, "SessionKeepSplits", settings.completedRun == "splits")
    writeIfChanged(status, "SessionRuns", settings.runs)
    store.saveClocks(status, record)
    writeIfChanged(status, "SessionIgtCs", record.igtCs)
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
    writeIfChanged(status, "SessionState", "")
    writeIfChanged(status, "SessionPaused", false)
    writeIfChanged(status, "SessionCategory", "")
    writeIfChanged(status, "SessionDistinct", "")
    writeIfChanged(status, "SessionSame", "")
    writeIfChanged(status, "SessionOnDeath", "")
    writeIfChanged(status, "SessionAllowed", "")
    writeIfChanged(status, "SessionKeepSplits", false)
    writeIfChanged(status, "SessionRuns", 0)
    writeIfChanged(status, "SessionRtaCs", 0)
    writeIfChanged(status, "SessionLoadCs", 0)
    writeIfChanged(status, "SessionIgtCs", 0)
    status.get(ATTEMPTS):clear()
end

--- The saved session record and its saved rules, or nil when nothing is saved.
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
        paused = status.read("SessionPaused") == true,
        attempts = attempts,
    }, {
        category = status.read("SessionCategory"),
        distinct = status.read("SessionDistinct"),
        same = status.read("SessionSame"),
        onDeath = status.read("SessionOnDeath"),
        allowed = decodeAllowed(status.read("SessionAllowed")),
        completedRun = status.read("SessionKeepSplits") == true and "splits" or "summary",
        runs = status.read("SessionRuns"),
    }
end

return store
