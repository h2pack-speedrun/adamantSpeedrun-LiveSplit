local data = import("data.lua")

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
local RECORDING_MODE_LABELS = {
    single = "Single run",
    multi = "Multi-run batch",
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
local RECORDING_MODE_OPTS = {
    values = data.recordingModes,
    default = "single",
    displayValues = RECORDING_MODE_LABELS,
    optionsPerLine = 2,
}
local RESUME_AFTER_RESTART_OPTS = {
    label = "Resume after restart",
    tooltip = "Keep the multi-run session across a game exit or crash. "
        .. "Time while the game is closed is not counted.",
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

local function drawRecordingControls(draw, state, actions, recordingMode, statusKind)
    if recordingMode == "multi" then
        draw.widgets.stepper(state.get("BatchTargetRuns"), BATCH_TARGET_RUNS_OPTS)
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
    draw.widgets.radio(state.get("RecordingMode"), RECORDING_MODE_OPTS)

    local recordingMode = readRecordingMode(state)
    drawRecordingControls(draw, state, actions, recordingMode, statusKind)

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

function module.drawTab(draw, state, actions, statusView)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, statusView, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, true)
end

function module.drawQuickContent(draw, state, actions, statusView)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, statusView, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, false)
end

function module.attach(libModule, statusView)
    libModule.ui.tab(function(_, ui)
        return module.drawTab(ui.draw, ui.data, ui.actions, statusView)
    end)
    libModule.ui.quickContent(function(_, ui)
        return module.drawQuickContent(ui.draw, ui.data, ui.actions, statusView)
    end)
end

return module
