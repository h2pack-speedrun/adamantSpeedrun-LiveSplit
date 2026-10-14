local data = {}

data.batchTargetRuns = {
    default = 3,
    min = 1,
    max = 10,
}

data.recordingModes = { "single", "multi" }

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
            type = "int",
            alias = "BatchTargetRuns",
            default = data.batchTargetRuns.default,
            min = data.batchTargetRuns.min,
            max = data.batchTargetRuns.max,
            hash = false,
        },
    }
end

function data.buildStatus()
    return {
        RecordingReady = {
            type = "bool",
            persist = true,
            default = false,
        },
    }
end

return data
