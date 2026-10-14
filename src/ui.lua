local data = import("data.lua")
local categories = import("timer/categories.lua")
local formatCentiseconds = import("display/time_format.lua").formatCentiseconds

local module = {}

local TIMER_MODE_OPTIONS = {
    {
        alias = "ShowIGT",
        label = "IGT",
        tooltip = "Show gameplay time from the in game timer.",
    },
    {
        alias = "ShowRTA",
        label = "RTA",
        tooltip = "Show real-time attack (wall-clock) time.",
    },
    {
        alias = "ShowLrT",
        label = "LrT",
        tooltip = "Show real time with map-load time removed.",
    },
}
local MUTED_TEXT_COLOR = { 0.65, 0.65, 0.65, 1.0 }
local WARNING_TEXT_COLOR = { 1.0, 0.78, 0.35, 1.0 }
local STATUS_TEXT_COLORS = {
    active = { 0.45, 0.85, 1.0, 1.0 },
    ready = { 0.55, 0.95, 0.55, 1.0 },
    failed = WARNING_TEXT_COLOR,
    recorded = { 0.80, 0.82, 0.88, 1.0 },
    idle = MUTED_TEXT_COLOR,
}
local MUTED_TEXT_OPTS = { color = MUTED_TEXT_COLOR }
local WARNING_TEXT_OPTS = { color = WARNING_TEXT_COLOR }
local TIMER_MODE_OPTS = {}
local SHOW_RAW_TIMERS_OPTS = {
    label = "Show raw run timer",
    tooltip = "Show compact IGT/RTA/LrT rows while recording is active.",
}
local SHOW_RECORDING_TABLE_OPTS = {
    label = "Show run splits",
    tooltip = "Show run split as a table while recording.",
}
local CATEGORY_OPTS = {
    label = "Category",
    values = categories.ORDER,
    displayValues = categories.NAMES,
    controlWidth = 180,
}
local CUSTOM_DISTINCT_OPTS = {
    label = "Each counted run needs a new",
    tooltip = "None counts every cleared run.",
    values = categories.KEY_VALUES,
    displayValues = categories.KEY_NAMES,
    controlWidth = 140,
}
local CUSTOM_SAME_OPTS = {
    label = "Every run must keep the same",
    tooltip = "Runs that change it are marked invalid and do not count.",
    values = categories.KEY_VALUES,
    displayValues = categories.KEY_NAMES,
    controlWidth = 140,
}
local CUSTOM_ON_DEATH_OPTS = {
    label = "On death",
    values = categories.ON_DEATH_VALUES,
    displayValues = categories.ON_DEATH_NAMES,
    controlWidth = 180,
}
local RESUME_AFTER_RESTART_OPTS = {
    label = "Resume after restart",
    tooltip = "Keep the multi-run session across a game exit or crash. "
        .. "Time while the game is closed is not counted.",
}
local PAGE_SIZE_OPTS = {
    label = "Runs per overlay page",
    min = data.pageSize.min,
    max = data.pageSize.max,
    default = data.pageSize.default,
}
local HISTORY_HEIGHT = 180
local HISTORY_STATUS_COLORS = {
    counted = { 0.80, 0.82, 0.88, 1.0 },
    failed = WARNING_TEXT_COLOR,
    duplicate = MUTED_TEXT_COLOR,
    invalid = MUTED_TEXT_COLOR,
}
local BATCH_TARGET_RUNS_OPTS = {
    label = "Runs to record",
    min = data.batchTargetRuns.min,
    max = data.batchTargetRuns.max,
    default = data.batchTargetRuns.default,
}
local START_RECORDING_OPTS = {
    id = "recording_start",
    value = true,
}
local RESTART_RECORDING_OPTS = {
    id = "recording_restart",
    value = true,
}
local CLEAR_RECORDING_OPTS = {
    id = "recording_clear",
    value = true,
}
local STOP_RECORDING_OPTS = {
    id = "recording_stop",
    value = true,
}

for _, option in ipairs(TIMER_MODE_OPTIONS) do
    TIMER_MODE_OPTS[option.alias] = {
        label = option.label,
        tooltip = option.tooltip,
    }
end

local function drawSection(draw, title, helpText)
    local imgui = draw.imgui
    if imgui.Spacing then
        imgui.Spacing()
    end
    draw.widgets.text(title)
    draw.widgets.separator()
    if helpText then
        draw.widgets.text(helpText, MUTED_TEXT_OPTS)
    end
end

local function enforceVisibleTimerMode(state)
    if state.read("ShowIGT") or state.read("ShowRTA") or state.read("ShowLrT") then
        return
    end
    state.write("ShowIGT", true)
end

local function readBool(state, alias, fallback)
    local value = state.read(alias)
    if value == nil then
        return fallback == true
    end
    return value == true
end

local function readRecordingMode(state)
    local mode = state.read("RecordingMode")
    local normalized = data.normalizeRecordingMode(mode)
    if normalized ~= mode then
        state.write("RecordingMode", normalized)
    end
    return normalized
end

--- The picker category. RecordingMode follows it; a setup from before categories existed (multi-run
--- mode) moves to Custom once, which keeps its old batch rules.
local function readCategory(state)
    if state.read("CategoryVersion") ~= 1 then
        if readRecordingMode(state) == "multi" then
            state.write("Category", categories.CUSTOM)
        end
        state.write("CategoryVersion", 1)
    end
    local category = state.read("Category")
    if categories.NAMES[category] == nil then
        category = categories.SINGLE
        state.write("Category", category)
    end
    local mode = category == categories.SINGLE and "single" or "multi"
    if readRecordingMode(state) ~= mode then
        state.write("RecordingMode", mode)
    end
    return category
end

local function withAction(opts, action)
    opts.action = action
    return opts
end

local function drawRecordingActions(draw, actions, statusKind)
    local imgui = draw.imgui
    local startAction = actions.get("recordingStart")
    local stopAction = actions.get("recordingStop")
    local clearAction = actions.get("recordingClear")

    if statusKind == "ready" or statusKind == "active" then
        draw.widgets.button("Stop", withAction(STOP_RECORDING_OPTS, stopAction))
        imgui.SameLine()
        draw.widgets.button("Clear", withAction(CLEAR_RECORDING_OPTS, clearAction))
        return
    end

    if statusKind == "recorded" or statusKind == "failed" then
        draw.widgets.button("Start New", withAction(RESTART_RECORDING_OPTS, startAction))
        imgui.SameLine()
        draw.widgets.button("Clear", withAction(CLEAR_RECORDING_OPTS, clearAction))
        return
    end

    draw.widgets.button("Start", withAction(START_RECORDING_OPTS, startAction))
end

local function getRecordingStatus(statusView)
    local status = statusView.getRecordingStatus()
    local statusText = status and status.text or "Not recording"
    local statusKind = status and status.kind or "idle"
    return statusKind, statusText
end

local function drawCustomRules(draw, state)
    draw.widgets.stepper(state.get("BatchTargetRuns"), BATCH_TARGET_RUNS_OPTS)
    draw.widgets.dropdown(state.get("CustomDistinct"), CUSTOM_DISTINCT_OPTS)
    draw.widgets.dropdown(state.get("CustomSame"), CUSTOM_SAME_OPTS)
    draw.widgets.dropdown(state.get("CustomOnDeath"), CUSTOM_ON_DEATH_OPTS)
end

local function drawRecordingControls(draw, state, actions, category, statusKind)
    draw.widgets.text(categories.RULES_TEXT[category] or "", MUTED_TEXT_OPTS)
    if category == categories.CUSTOM then
        drawCustomRules(draw, state)
    end
    if category ~= categories.SINGLE then
        draw.widgets.checkbox(state.get("ResumeAfterRestart"), RESUME_AFTER_RESTART_OPTS)
    end

    drawRecordingActions(draw, actions, statusKind)
end

local function drawRecordingSection(draw, state, actions, statusView, showRecordingTable, showRawTimers)
    drawSection(draw, "Recording")
    local statusKind, statusText = getRecordingStatus(statusView)
    draw.widgets.text("Status: " .. statusText, {
        color = STATUS_TEXT_COLORS[statusKind] or MUTED_TEXT_COLOR,
    })
    draw.widgets.dropdown(state.get("Category"), CATEGORY_OPTS)

    local category = readCategory(state)
    drawRecordingControls(draw, state, actions, category, statusKind)

    if statusKind == "active" and not showRecordingTable and not showRawTimers then
        draw.widgets.text(
            "Recording is active, but no timer output is visible.",
            WARNING_TEXT_OPTS)
    elseif statusKind ~= "idle" and not showRecordingTable then
        draw.widgets.text(
            "Recording table is hidden, so recorded rows will not be visible.",
            WARNING_TEXT_OPTS)
    end
end

local function drawDisplaySection(draw, state, includeColumns)
    drawSection(draw, "Display During Recording")
    draw.widgets.checkbox(state.get("ShowRecordingTable"), SHOW_RECORDING_TABLE_OPTS)
    draw.widgets.checkbox(state.get("ShowRawTimers"), SHOW_RAW_TIMERS_OPTS)

    if includeColumns then
        draw.widgets.text("Timer columns", MUTED_TEXT_OPTS)
        for _, option in ipairs(TIMER_MODE_OPTIONS) do
            draw.widgets.checkbox(state.get(option.alias), TIMER_MODE_OPTS[option.alias])
        end
        enforceVisibleTimerMode(state)
    end
end

local function drawPagingSection(draw, state, hotkeys)
    drawSection(draw, "Multi-Run Overlay Pages",
        "The overlay shows one page of finished runs; the keys page through older ones.")
    draw.widgets.stepper(state.get("PageSize"), PAGE_SIZE_OPTS)
    draw.widgets.hotkey(hotkeys.get(data.pageKeys.previous.id))
    draw.widgets.hotkey(hotkeys.get(data.pageKeys.next.id))
end

-- Formatted history lines, cached by the history list they were built from.
local historyLines = {
    source = nil,
    lines = {},
}

local function formatOptional(valueCs)
    return valueCs ~= nil and formatCentiseconds(valueCs) or "--"
end

local function getHistoryLines(history)
    if history == historyLines.source then
        return historyLines.lines
    end
    local lines = {}
    for index, entry in ipairs(history) do
        lines[index] = {
            text = ("%3d  %-10s  IGT %s  RTA %s  LrT %s"):format(index, entry.label,
                formatOptional(entry.sessionIgtCs), formatOptional(entry.sessionRtaCs),
                formatOptional(entry.sessionLrtCs)),
            opts = { color = HISTORY_STATUS_COLORS[entry.status] or MUTED_TEXT_COLOR },
        }
    end
    historyLines.source = history
    historyLines.lines = lines
    return lines
end

local function drawHistorySection(draw, statusView)
    local history = statusView.getSessionHistory()
    if #history == 0 then
        return
    end
    drawSection(draw, "Session History", "Every finished run in this session, with session totals at its end.")
    local imgui = draw.imgui
    local scrolling = imgui.BeginChild ~= nil
    if scrolling then
        imgui.BeginChild("LiveSplitSessionHistory", 0, HISTORY_HEIGHT, true)
    end
    for _, line in ipairs(getHistoryLines(history)) do
        draw.widgets.text(line.text, line.opts)
    end
    if scrolling then
        imgui.EndChild()
    end
end

function module.drawTab(draw, state, actions, statusView, hotkeys)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, statusView, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, true)
    if readRecordingMode(state) == "multi" then
        drawPagingSection(draw, state, hotkeys)
        drawHistorySection(draw, statusView)
    end
end

function module.drawQuickContent(draw, state, actions, statusView)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, statusView, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, false)
end

function module.attach(libModule, statusView)
    libModule.ui.tab(function(_, ui)
        return module.drawTab(ui.draw, ui.data, ui.actions, statusView, ui.hotkeys)
    end)
    libModule.ui.quickContent(function(_, ui)
        return module.drawQuickContent(ui.draw, ui.data, ui.actions, statusView)
    end)
end

return module
