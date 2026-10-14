local data = {}

data.batchTargetRuns = {
    default = 3,
    min = 1,
    max = 10,
}

data.recordingModes = { "single", "multi" }

-- Finished attempts per overlay page.
data.pageSize = {
    default = 5,
    min = 1,
    max = 10,
}

-- Page keys are Lib-managed hotkeys (module.hotkeys). Their bindings keep the PagePrevKey and
-- PageNextKey storage aliases so saved keys carry over.
data.pageKeys = {
    previous = { id = "PagePrev", alias = "PagePrevKey", default = "F7" },
    next = { id = "PageNext", alias = "PageNextKey", default = "F8" },
}

function data.normalizeRecordingMode(mode)
    if mode == "multi" then
        return "multi"
    end
    return "single"
end

function data.buildStorage()
    return {
        {
            type = "bool",
            alias = "ShowIGT",
            default = true,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRTA",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowLrT",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRawTimers",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRecordingTable",
            default = true,
            hash = false,
        },
        {
            type = "string",
            alias = "RecordingMode",
            default = "single",
            maxLen = 16,
            hash = false,
        },
        -- Picker choice: "single", a preset, or "custom" (see timer/categories.lua). RecordingMode
        -- follows it ("single" or "multi").
        {
            type = "string",
            alias = "Category",
            default = "single",
            maxLen = 16,
            hash = false,
        },
        -- 1 once a pre-category multi-run setup has been moved to the Custom category.
        { type = "int", alias = "CategoryVersion", default = 0, hash = false },
        { type = "string", alias = "CustomDistinct", default = "none", maxLen = 16, hash = false },
        { type = "string", alias = "CustomSame", default = "none", maxLen = 16, hash = false },
        { type = "string", alias = "CustomOnDeath", default = "reset", maxLen = 16, hash = false },
        {
            type = "bool",
            alias = "ResumeAfterRestart",
            default = true,
            hash = false,
        },
        {
            type = "int",
            alias = "PageSize",
            default = data.pageSize.default,
            min = data.pageSize.min,
            max = data.pageSize.max,
            hash = false,
        },
        {
            type = "int",
            alias = "BatchTargetRuns",
            default = data.batchTargetRuns.default,
            min = data.batchTargetRuns.min,
            max = data.batchTargetRuns.max,
            hash = false,
        },
    }
end

-- Upper bound on saved attempts in one session (successes, failures and duplicates together).
-- Every save rewrites the whole module config file (about 1.5 KB per attempt with biome splits).
data.maxSessionAttempts = 200
-- Biome splits saved per attempt (categories that keep splits).
data.maxAttemptBiomes = 4

local function persistedInt(default)
    return { type = "int", persist = true, default = default or 0 }
end

local function attemptColumns()
    local columns = {
        { type = "string", alias = "Status", default = "", maxLen = 16 },
        { type = "string", alias = "Route", default = "", maxLen = 16 },
        { type = "string", alias = "Weapon", default = "", maxLen = 64 },
        { type = "string", alias = "Aspect", default = "", maxLen = 64 },
        { type = "int", alias = "RunOrdinal", default = -1 },
        { type = "int", alias = "IgtCs", default = 0 },
        { type = "int", alias = "SessionIgtCs", default = 0 },
        { type = "int", alias = "SessionRtaCs", default = 0 },
        { type = "int", alias = "SessionLrtCs", default = 0 },
        { type = "int", alias = "CountIndex", default = 0 },
    }
    -- Biome split N: B<N>Code (biome room set, empty when unused) and its session times.
    for index = 1, data.maxAttemptBiomes do
        local prefix = "B" .. index
        columns[#columns + 1] = { type = "string", alias = prefix .. "Code", default = "", maxLen = 4 }
        columns[#columns + 1] = { type = "int", alias = prefix .. "IgtCs", default = 0 }
        columns[#columns + 1] = { type = "int", alias = prefix .. "RtaCs", default = 0 }
        columns[#columns + 1] = { type = "int", alias = prefix .. "LrtCs", default = 0 }
    end
    return columns
end

function data.buildStatus()
    return {
        RecordingReady = {
            type = "bool",
            persist = true,
            default = false,
        },
        -- The saved multi-run session; see timer/session_store.lua.
        SessionState = { type = "string", persist = true, default = "", maxLen = 16 },
        -- The session's rules, so a resumed session keeps them even if settings changed.
        SessionCategory = { type = "string", persist = true, default = "", maxLen = 16 },
        SessionDistinct = { type = "string", persist = true, default = "", maxLen = 16 },
        SessionSame = { type = "string", persist = true, default = "", maxLen = 16 },
        SessionOnDeath = { type = "string", persist = true, default = "", maxLen = 16 },
        SessionRuns = persistedInt(),
        SessionRtaCs = persistedInt(),
        SessionLoadCs = persistedInt(),
        SessionIgtCs = persistedInt(),
        SessionAttempts = {
            type = "table",
            persist = true,
            maxRows = data.maxSessionAttempts,
            row = attemptColumns(),
        },
    }
end

return data
