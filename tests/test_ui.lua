local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual

local uiStatus = {
    kind = "idle",
    text = "Not recording",
}
local uiModule = support.withImport(function()
    return assert(loadfile("src/ui.lua"))()
end)
local uiStatusView = {
    getRecordingStatus = function()
        return uiStatus
    end,
}

local uiSessionValues = {
    ShowIGT = false,
    ShowRTA = false,
    ShowLrT = false,
    ShowRawTimers = false,
    ShowRecordingTable = true,
    RecordingMode = "single",
}
local uiSessionActions = {}
local uiButtons = {}
local uiStepperOpts = nil
local uiDraw = {
    imgui = {
        SameLine = function() end,
        Spacing = function() end,
    },
    widgets = {
        text = function() end,
        separator = function() end,
        checkbox = function() return false end,
        radio = function() return false end,
        stepper = function(_, opts)
            uiStepperOpts = opts
            return false
        end,
        button = function(label, opts)
            uiButtons[#uiButtons + 1] = label
            opts.action:stage(opts.value)
            return true
        end,
    },
}
local drawState = {
    get = function(alias)
        return {
            alias = alias,
        }
    end,
    read = function(alias)
        return uiSessionValues[alias]
    end,
    write = function(alias, value)
        uiSessionValues[alias] = value
    end,
}
local uiActions = {
    get = function(action)
        return {
            stage = function(_, value)
                uiSessionActions[action] = value
            end,
        }
    end,
}
uiModule.drawTab({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionValues.ShowIGT, true)
assertEqual(uiSessionActions.recordingStart, true)
assertEqual(uiButtons[1], "Start")
assertEqual(uiButtons[2], nil)

uiSessionActions = {}
uiButtons = {}
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionActions.recordingStart, true)
assertEqual(uiButtons[1], "Start")
assertEqual(uiButtons[2], nil)

uiStatus = {
    kind = "active",
    text = "Recording current run",
}
uiSessionActions = {}
uiButtons = {}
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionActions.recordingStop, true)
assertEqual(uiSessionActions.recordingClear, true)
assertEqual(uiButtons[1], "Stop")
assertEqual(uiButtons[2], "Clear")
assertEqual(uiButtons[3], nil)

uiSessionValues.RecordingMode = "multi"
uiStepperOpts = nil
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiStepperOpts.max, support.data.batchTargetRuns.max)
