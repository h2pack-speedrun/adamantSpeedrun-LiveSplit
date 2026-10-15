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
    OverlayMode = "table",
    RecordingMode = "single",
    BatchTargetRuns = 3,
    CustomDistinct = "none",
    CustomSame = "none",
    CustomOnDeath = "reset",
}
local uiSessionActions = {}
local uiButtons = {}
local uiStepperOpts = nil
local uiDraw = {
    imgui = {
        SameLine = function() end,
        Spacing = function() end,
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = function() end,
        AlignTextToFramePadding = function() end,
        CalcTextSize = function(text) return #text * 7, 14 end,
        GetContentRegionAvail = function() return 600, 400 end,
        IsItemHovered = function() return false end,
    },
    widgets = {
        text = function() end,
        separator = function() end,
        checkbox = function() return false end,
        radio = function() return false end,
        dropdown = function() return false end,
        confirmButton = function() return false end,
        slider = function(field, opts)
            if field.alias == "BatchTargetRuns" then
                uiStepperOpts = opts
            end
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
local firstDraw = {
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}
uiModule.drawRecordingTab(firstDraw, drawState, uiActions, uiStatusView)
uiModule.drawSettingsTab(firstDraw, drawState)
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

-- Custom's run count is edited in the Settings tab, up to 50 runs.
uiSessionValues.Category = "custom"
uiStepperOpts = nil
uiModule.drawSettingsTab({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState)
assertEqual(uiStepperOpts.max, 50)

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
local hotkeyRefs = {}
local childDepth = 0
local fullDraw = {
    imgui = {
        SameLine = function() end,
        Spacing = function() end,
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = function() end,
        AlignTextToFramePadding = function() end,
        CalcTextSize = function(text) return #text * 7, 14 end,
        GetContentRegionAvail = function() return 600, 400 end,
        IsItemHovered = function() return false end,
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
        slider = function() return false end,
        confirmButton = function() return false end,
        dropdown = function(field)
            dropdownLabels[#dropdownLabels + 1] = field.alias
            return false
        end,
        hotkey = function(ref)
            hotkeyRefs[#hotkeyRefs + 1] = ref
            return false
        end,
        button = function(_, opts)
            opts.action:stage(opts.value)
            return true
        end,
    },
}
uiSessionValues.Category = "custom"
uiModule.drawRecordingTab(fullDraw, drawState, uiActions, historyView)
uiModule.drawSettingsTab(fullDraw, drawState)
local function hasDropdown(label)
    for _, value in ipairs(dropdownLabels) do
        if value == label then
            return true
        end
    end
    return false
end
-- The category picker leads the Recording tab, on the actions' row.
assertEqual(dropdownLabels[1], "Category")
assert(hasDropdown("CustomDistinct"), "expected custom rule dropdowns")
-- Page keys are drawn by Lib in the module header, not by LiveSplit.
assertEqual(#hotkeyRefs, 0)
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
uiModule.drawRecordingTab(fullDraw, drawState, uiActions, historyView)
uiModule.drawSettingsTab(fullDraw, drawState)
local cachedLine = nil
for _, entry in ipairs(texts) do
    if entry.text:find("^%s*1  ") then
        cachedLine = entry.text
    end
end
assert(rawequal(cachedLine, firstLine), "expected cached history line")
uiSessionValues.Category = "single"

-- The module declares two top-level tabs; Lib adds Hotkeys & Advanced after them.
local declaredTabs = nil
uiModule.attach({
    ui = {
        tabs = function(list)
            declaredTabs = list
        end,
        quickContent = function() end,
    },
}, historyView)
assertEqual(#declaredTabs, 2)
assertEqual(declaredTabs[1].id, "recording")
assertEqual(declaredTabs[1].label, "Recording")
assertEqual(declaredTabs[2].id, "settings")
assertEqual(declaredTabs[2].label, "Settings")

-- Settings: presets show read-only rules (no Resume checkbox); Custom edits its rules.
local function checkboxLabelsFor(category)
    uiSessionValues.Category = category
    local labels = {}
    local recordingDraw = {
        imgui = fullDraw.imgui,
        widgets = setmetatable({
            checkbox = function(field, opts)
                -- Rule checkboxes sit under a row label; they must not fall back to the alias.
                assert(opts.label ~= nil, field.alias)
                labels[#labels + 1] = field.alias
                return false
            end,
        }, { __index = fullDraw.widgets }),
    }
    uiModule.drawSettingsTab(recordingDraw, drawState)
    return labels
end
local function hasLabel(labels, wanted)
    for _, label in ipairs(labels) do
        if label == wanted then
            return true
        end
    end
    return false
end
assert(not hasLabel(checkboxLabelsFor("allWeapons"), "ResumeAfterRestart"), "presets hide resume")
assert(hasLabel(checkboxLabelsFor("custom"), "ResumeAfterRestart"), "custom shows resume")
assert(hasLabel(checkboxLabelsFor("custom"), "CustomKeepSplits"), "custom shows keep splits")
assert(not hasLabel(checkboxLabelsFor("custom"), "CustomAllowUnderworld"), "regions only for a new region")
uiSessionValues.CustomDistinct = "route"
assert(hasLabel(checkboxLabelsFor("custom"), "CustomAllowDream"), "regions for a new region")

-- Custom offers only compatible "same" keys and caps runs at what the distinct key allows.
local sameOpts = nil
uiSessionValues.Category = "custom"
uiSessionValues.CustomDistinct = "weapon"
uiSessionValues.CustomSame = "weapon"
uiSessionValues.BatchTargetRuns = 30
uiModule.drawSettingsTab({
    imgui = fullDraw.imgui,
    widgets = setmetatable({
        dropdown = function(field, opts)
            if field.alias == "CustomSame" then
                sameOpts = opts
            end
            return false
        end,
    }, { __index = fullDraw.widgets }),
}, drawState)
assertEqual(uiSessionValues.CustomSame, "none")
assertEqual(uiSessionValues.BatchTargetRuns, 6)
assertEqual(sameOpts.visibleValues.weapon, false)
assertEqual(sameOpts.visibleValues.aspect, false)
assertEqual(sameOpts.visibleValues.route, true)

-- Copy to Custom writes the preset's rules into Custom and switches the picker.
uiSessionValues.Category = "allRegions"
uiModule.drawSettingsTab({
    imgui = fullDraw.imgui,
    widgets = setmetatable({
        confirmButton = function()
            return true
        end,
    }, { __index = fullDraw.widgets }),
}, drawState)
assertEqual(uiSessionValues.Category, "custom")
assertEqual(uiSessionValues.BatchTargetRuns, 2)
assertEqual(uiSessionValues.CustomDistinct, "route")
assertEqual(uiSessionValues.CustomSame, "aspect")
assertEqual(uiSessionValues.CustomOnDeath, "continue")
assertEqual(uiSessionValues.CustomAllowDream, false)
assertEqual(uiSessionValues.CustomKeepSplits, true)
assertEqual(uiSessionValues.ResumeAfterRestart, true)

-- Session history sits under a header that is collapsed by default.
uiSessionValues.Category = "allWeapons"
local historyTextCount = 0
local collapsedDraw = {
    imgui = setmetatable({
        CollapsingHeader = function()
            return false
        end,
    }, { __index = fullDraw.imgui }),
    widgets = setmetatable({
        text = function(text)
            if text:find("^%s*%d+  ") then
                historyTextCount = historyTextCount + 1
            end
        end,
    }, { __index = fullDraw.widgets }),
}
uiModule.drawRecordingTab(collapsedDraw, drawState, uiActions, historyView)
assertEqual(historyTextCount, 0)
uiSessionValues.Category = "single"

-- Between runs the action row leads with Pause; while paused, with Resume. Both stage the pause action.
local function actionButtonsFor(status)
    uiStatus = status
    uiButtons = {}
    uiSessionActions = {}
    uiModule.drawRecordingTab({
        imgui = fullDraw.imgui,
        widgets = setmetatable({
            button = uiDraw.widgets.button,
        }, { __index = fullDraw.widgets }),
    }, drawState, uiActions, historyView)
    return uiButtons
end
uiSessionValues.Category = "allWeapons"
local betweenRuns = actionButtonsFor({ kind = "active", text = "Recording 1 / 6", canPause = true })
assertEqual(betweenRuns[1], "Pause")
assertEqual(betweenRuns[2], "Stop")
assertEqual(uiSessionActions.recordingPause, true)
local paused = actionButtonsFor({ kind = "paused", text = "Paused (1 / 6)", canResume = true })
assertEqual(paused[1], "Resume")
assertEqual(paused[2], "Stop")
local inRun = actionButtonsFor({ kind = "active", text = "Recording 1 / 6", canPause = false })
assertEqual(inRun[1], "Stop")
uiSessionValues.Category = "single"
