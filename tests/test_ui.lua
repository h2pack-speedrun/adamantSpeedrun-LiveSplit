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
        dropdown = function() return false end,
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

uiSessionValues.Category = "custom"
uiStepperOpts = nil
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiStepperOpts.max, support.data.batchTargetRuns.max)

-- Full tab in multi-run mode: paging settings and the scrollable session history.
local historyEntries = {
    { label = "Run 1/3", status = "counted", sessionIgtCs = 6000, sessionRtaCs = 7000, sessionLrtCs = 6500 },
    { label = "Failed", status = "failed", sessionIgtCs = 9000, sessionRtaCs = 11000, sessionLrtCs = nil },
}
local historyView = {
    getRecordingStatus = function()
        return uiStatus
    end,
    getSessionHistory = function()
        return historyEntries
    end,
}
local texts = {}
local dropdownLabels = {}
local childDepth = 0
local fullDraw = {
    imgui = {
        SameLine = function() end,
        Spacing = function() end,
        BeginChild = function()
            childDepth = childDepth + 1
        end,
        EndChild = function()
            childDepth = childDepth - 1
        end,
    },
    widgets = {
        text = function(text, opts)
            texts[#texts + 1] = { text = text, opts = opts }
        end,
        separator = function() end,
        checkbox = function() return false end,
        radio = function() return false end,
        stepper = function() return false end,
        dropdown = function(_, opts)
            dropdownLabels[#dropdownLabels + 1] = opts.label
            return false
        end,
        button = function(_, opts)
            opts.action:stage(opts.value)
            return true
        end,
    },
}
uiSessionValues.Category = "custom"
uiModule.drawTab(fullDraw, drawState, uiActions, historyView)
local function hasDropdown(label)
    for _, value in ipairs(dropdownLabels) do
        if value == label then
            return true
        end
    end
    return false
end
assertEqual(dropdownLabels[1], "Category")
assert(hasDropdown("Each counted run needs a new"), "expected custom rule dropdowns")
assert(hasDropdown("Previous page key"), "expected previous page key")
assert(hasDropdown("Next page key"), "expected next page key")
assertEqual(childDepth, 0)
local historyTexts = {}
for _, entry in ipairs(texts) do
    if entry.text:find("^%s*%d+  ") then
        historyTexts[#historyTexts + 1] = entry
    end
end
assertEqual(#historyTexts, 2)
assert(historyTexts[1].text:find("Run 1/3", 1, true), historyTexts[1].text)
assert(historyTexts[1].text:find("RTA 01:10.00", 1, true), historyTexts[1].text)
assert(historyTexts[2].text:find("LrT --", 1, true), historyTexts[2].text)
-- History lines are cached while the history list is unchanged.
local firstLine = historyTexts[1].text
texts = {}
uiModule.drawTab(fullDraw, drawState, uiActions, historyView)
local cachedLine = nil
for _, entry in ipairs(texts) do
    if entry.text:find("^%s*1  ") then
        cachedLine = entry.text
    end
end
assert(rawequal(cachedLine, firstLine), "expected cached history line")
uiSessionValues.Category = "single"
