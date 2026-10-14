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

-- Page hotkeys follow Quick Pause: F1 opens the Hell2Modding overlay, and Quick Pause defaults
-- to F9, so LiveSplit defaults to F7 and F8.
data.HOTKEY_NONE = ""
data.hotkeyValues = { data.HOTKEY_NONE, "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" }
data.hotkeyDisplayValues = { [data.HOTKEY_NONE] = "None" }

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
            type = "string",
            alias = "PagePrevKey",
            default = "F7",
            maxLen = 8,
            hash = false,
        },
        {
            type = "string",
            alias = "PageNextKey",
            default = "F8",
            maxLen = 8,
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
data.maxSessionAttempts = 500

local function persistedInt(default)
    return { type = "int", persist = true, default = default or 0 }
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
        SessionRuns = persistedInt(),
        SessionRtaCs = persistedInt(),
        SessionLoadCs = persistedInt(),
        SessionIgtCs = persistedInt(),
        SessionAttempts = {
            type = "table",
            persist = true,
            maxRows = data.maxSessionAttempts,
            row = {
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
            },
        },
    }
end

return data
