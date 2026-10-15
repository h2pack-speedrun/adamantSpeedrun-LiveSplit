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
    paused = { 0.95, 0.85, 0.45, 1.0 },
    ready = { 0.55, 0.95, 0.55, 1.0 },
    failed = WARNING_TEXT_COLOR,
    recorded = { 0.80, 0.82, 0.88, 1.0 },
    idle = MUTED_TEXT_COLOR,
}
local MUTED_TEXT_OPTS = { color = MUTED_TEXT_COLOR }
local TIMER_MODE_OPTS = {}
-- Settings rows share one layout in both tabs: a muted label column, measured from the widest
-- label with the current font, then the value or control. Labels are drawn here, not by the
-- widgets, so every row's label looks the same.
local LABEL_COLUMN_GAP = 24
local COPY_BUTTON_LABEL = "Copy to Custom"
-- Button width beyond its label text (frame padding on both sides).
local BUTTON_PADDING = 16

local OVERLAY_LABEL = "Overlay"
local COLUMNS_LABEL = "Columns"
local PAGE_SIZE_LABEL = "Runs per page"
local DISPLAY_LABELS = { OVERLAY_LABEL, COLUMNS_LABEL, PAGE_SIZE_LABEL }
local OVERLAY_MODE_OPTS = {
    values = data.overlayModes,
    displayValues = data.overlayModeNames,
    controlWidth = 180,
}
local PAGE_SIZE_OPTS = {
    controlWidth = 180,
    min = data.pageSize.min,
    max = data.pageSize.max,
    default = data.pageSize.default,
}

local CATEGORY_OPTS = {
    values = categories.ORDER,
    displayValues = categories.NAMES,
    controlWidth = 160,
}
local RUNS_ROW = { label = "Runs needed" }
local DISTINCT_ROW = { label = "Each counted run needs a new", tooltip = "None counts every cleared run." }
local ALLOWED_ROW = { label = "Allowed regions" }
local SAME_ROW = {
    label = "Every run must keep the same",
    tooltip = "Runs that change it are marked invalid and do not count.",
}
local ON_DEATH_ROW = { label = "On death" }
local KEEP_SPLITS_ROW = {
    label = "Keep biome splits per run",
    tooltip = "Show each counted run's biome splits in the session, as All Regions does.",
}
local RESUME_ROW = {
    label = "Resume after restart",
    tooltip = "Keep the multi-run session across a game exit or crash. "
        .. "Time while the game is closed is not counted.",
}
local RULE_LABELS = {
    RUNS_ROW.label,
    DISTINCT_ROW.label,
    ALLOWED_ROW.label,
    SAME_ROW.label,
    ON_DEATH_ROW.label,
    KEEP_SPLITS_ROW.label,
    RESUME_ROW.label,
}

local CUSTOM_RUNS_OPTS = {
    controlWidth = 180,
    min = data.batchTargetRuns.min,
    max = data.batchTargetRuns.max,
    default = data.batchTargetRuns.default,
}
local DISTINCT_DROPDOWN_OPTS = {
    values = categories.KEY_VALUES,
    displayValues = categories.KEY_NAMES,
    controlWidth = 140,
}
-- Offers only the values compatible with the chosen distinct key; refreshed every frame.
local SAME_DROPDOWN_OPTS = {
    values = categories.KEY_VALUES,
    displayValues = categories.KEY_NAMES,
    visibleValues = {},
    controlWidth = 140,
}
local ON_DEATH_OPTS = {
    values = categories.ON_DEATH_VALUES,
    displayValues = categories.ON_DEATH_NAMES,
    controlWidth = 180,
}
local REGION_OPTS = {}
for _, region in ipairs(categories.REGIONS) do
    REGION_OPTS[region.alias] = { label = region.name }
end
-- An empty label: without one the checkbox widget falls back to the field alias.
local UNLABELED_OPTS = { label = "" }
local COPY_TO_CUSTOM_OPTS = {
    confirmLabel = "Overwrite Custom",
    tooltip = "Replace Custom's rules with this category's and switch to Custom.",
}
local HISTORY_HEIGHT = 180
local HISTORY_HEADER = "Session History##livesplit-history"
local HISTORY_STATUS_COLORS = {
    counted = { 0.80, 0.82, 0.88, 1.0 },
    failed = WARNING_TEXT_COLOR,
    duplicate = MUTED_TEXT_COLOR,
    invalid = MUTED_TEXT_COLOR,
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
local PAUSE_RECORDING_OPTS = {
    id = "recording_pause",
    value = true,
    tooltip = "Stops the session clocks for a break; starting a run resumes. Also on the Pause session key.",
}
local RESUME_RECORDING_OPTS = {
    id = "recording_resume",
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

local function enforceVisibleTimerMode(state)
    if state.read("ShowIGT") or state.read("ShowRTA") or state.read("ShowLrT") then
        return
    end
    state.write("ShowIGT", true)
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

local function drawRecordingActions(draw, actions, status)
    local imgui = draw.imgui
    local statusKind = status.kind
    local startAction = actions.get("recordingStart")
    local stopAction = actions.get("recordingStop")
    local clearAction = actions.get("recordingClear")

    -- Pause and Resume lead the row while the session is between runs.
    if status.canResume then
        draw.widgets.button("Resume", withAction(RESUME_RECORDING_OPTS, actions.get("recordingPause")))
        imgui.SameLine()
    elseif status.canPause then
        draw.widgets.button("Pause", withAction(PAUSE_RECORDING_OPTS, actions.get("recordingPause")))
        imgui.SameLine()
    end

    if statusKind == "ready" or statusKind == "active" or statusKind == "paused" then
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

local IDLE_STATUS = { kind = "idle", text = "Not recording" }

local function rulesLine(state, category)
    if category == categories.SINGLE then
        return categories.RULES_TEXT.single
    end
    return categories.summary(categories.settingsFor(category, state))
end

--- Category picker and actions on one row, then the status and the category's rules under it.
local function drawRecordingSection(draw, state, actions, statusView)
    local status = statusView.getRecordingStatus() or IDLE_STATUS
    draw.widgets.dropdown(state.get("Category"), CATEGORY_OPTS)
    local category = readCategory(state)
    draw.imgui.SameLine()
    drawRecordingActions(draw, actions, status)

    draw.widgets.text(status.text, {
        color = STATUS_TEXT_COLORS[status.kind] or MUTED_TEXT_COLOR,
    })
    draw.widgets.text(rulesLine(state, category), MUTED_TEXT_OPTS)
end

local function measureLabelColumn(imgui, labels)
    local widest = 0
    for _, label in ipairs(labels) do
        widest = math.max(widest, (imgui.CalcTextSize(label)))
    end
    return widest + LABEL_COLUMN_GAP
end

-- A row's muted label; the cursor is left at the value column. `aligned` centres the label on a
-- control's frame height, for rows that hold a control.
local function drawRowLabel(draw, row, columnWidth, aligned)
    local imgui = draw.imgui
    local rowStartX = imgui.GetCursorPosX()
    if aligned then
        imgui.AlignTextToFramePadding()
    end
    draw.widgets.text(row.label, MUTED_TEXT_OPTS)
    if row.tooltip ~= nil and imgui.IsItemHovered() then
        imgui.SetTooltip(row.tooltip)
    end
    imgui.SameLine()
    imgui.SetCursorPosX(rowStartX + columnWidth)
end

-- Category name, a muted note, and an optional action button at the right edge of the row.
local function drawRulesHeader(draw, category, note)
    local imgui = draw.imgui
    local preset = categories.isPreset(category)
    local rowStartX = imgui.GetCursorPosX()
    local available = imgui.GetContentRegionAvail()
    if preset then
        imgui.AlignTextToFramePadding()
    end
    draw.widgets.text(categories.NAMES[category])
    if note ~= nil then
        imgui.SameLine()
        draw.widgets.text(note, MUTED_TEXT_OPTS)
    end
    if not preset then
        return false
    end
    imgui.SameLine()
    local buttonWidth = imgui.CalcTextSize(COPY_BUTTON_LABEL) + BUTTON_PADDING
    imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), rowStartX + available - buttonWidth))
    return draw.widgets.confirmButton("livesplit_copy_to_custom", COPY_BUTTON_LABEL, COPY_TO_CUSTOM_OPTS)
end

local function drawPresetRules(draw, category, columnWidth)
    local settings = categories.settingsFor(category)
    local function row(spec, value)
        drawRowLabel(draw, spec, columnWidth, false)
        draw.widgets.text(value)
    end
    row(RUNS_ROW, tostring(settings.runs))
    row(DISTINCT_ROW, categories.KEY_NAMES[settings.distinct])
    local allowed = categories.allowedText(settings.allowed)
    if allowed ~= nil then
        row(ALLOWED_ROW, allowed)
    end
    row(SAME_ROW, categories.KEY_NAMES[settings.same])
    row(ON_DEATH_ROW, categories.ON_DEATH_NAMES[settings.onDeath])
    row(KEEP_SPLITS_ROW, settings.completedRun == "splits" and "Yes" or "No")
    row(RESUME_ROW, "Always")
end

-- Region checkboxes on one row; the last checked region cannot be cleared.
local function drawAllowedRegions(draw, state, columnWidth)
    drawRowLabel(draw, ALLOWED_ROW, columnWidth, true)
    local checked = 0
    for _, region in ipairs(categories.REGIONS) do
        if state.read(region.alias) ~= false then
            checked = checked + 1
        end
    end
    for index, region in ipairs(categories.REGIONS) do
        if index > 1 then
            draw.imgui.SameLine()
        end
        local wasChecked = state.read(region.alias) ~= false
        draw.widgets.checkbox(state.get(region.alias), REGION_OPTS[region.alias])
        if wasChecked and checked == 1 and state.read(region.alias) == false then
            state.write(region.alias, true)
        end
    end
end

-- Keeps Custom's rules finishable as they are edited: an incompatible same key resets to None and
-- the run count drops to what the distinct key allows. categories.settingsFor enforces the same.
local function fitCustomRules(state)
    local settings = categories.settingsFor(categories.CUSTOM, state)
    if state.read("CustomSame") ~= settings.same then
        state.write("CustomSame", settings.same)
    end
    if state.read("BatchTargetRuns") ~= settings.runs then
        state.write("BatchTargetRuns", settings.runs)
    end
    local maxRuns = categories.maxRuns(settings.distinct, settings.same, settings.allowed)
    CUSTOM_RUNS_OPTS.max = maxRuns or data.batchTargetRuns.max
    for _, value in ipairs(categories.KEY_VALUES) do
        SAME_DROPDOWN_OPTS.visibleValues[value] = categories.compatibleSame(settings.distinct, value)
    end
end

local function drawCustomRules(draw, state, columnWidth)
    fitCustomRules(state)
    drawRowLabel(draw, RUNS_ROW, columnWidth, true)
    draw.widgets.slider(state.get("BatchTargetRuns"), CUSTOM_RUNS_OPTS)
    drawRowLabel(draw, DISTINCT_ROW, columnWidth, true)
    draw.widgets.dropdown(state.get("CustomDistinct"), DISTINCT_DROPDOWN_OPTS)
    if state.read("CustomDistinct") == "route" then
        drawAllowedRegions(draw, state, columnWidth)
    end
    drawRowLabel(draw, SAME_ROW, columnWidth, true)
    draw.widgets.dropdown(state.get("CustomSame"), SAME_DROPDOWN_OPTS)
    drawRowLabel(draw, ON_DEATH_ROW, columnWidth, true)
    draw.widgets.dropdown(state.get("CustomOnDeath"), ON_DEATH_OPTS)
    drawRowLabel(draw, KEEP_SPLITS_ROW, columnWidth, true)
    draw.widgets.checkbox(state.get("CustomKeepSplits"), UNLABELED_OPTS)
    drawRowLabel(draw, RESUME_ROW, columnWidth, true)
    draw.widgets.checkbox(state.get("ResumeAfterRestart"), UNLABELED_OPTS)
end

local function drawRulesSection(draw, state, category)
    if category == categories.SINGLE then
        drawRulesHeader(draw, category, nil)
        draw.widgets.text("Records each run's biome splits; it has no session rules.", MUTED_TEXT_OPTS)
        return
    end
    local preset = categories.isPreset(category)
    if drawRulesHeader(draw, category, preset and "(preset)" or nil) then
        categories.copyToCustom(category, state)
        state.write("Category", categories.CUSTOM)
        return
    end
    if preset then
        draw.widgets.text(categories.RULES_TEXT[category], MUTED_TEXT_OPTS)
    else
        draw.widgets.text("Changes apply when a session starts; a running session keeps its rules.", MUTED_TEXT_OPTS)
    end
    draw.widgets.separator()
    local columnWidth = measureLabelColumn(draw.imgui, RULE_LABELS)
    if preset then
        drawPresetRules(draw, category, columnWidth)
    else
        drawCustomRules(draw, state, columnWidth)
    end
end

local OVERLAY_ROW = {
    label = OVERLAY_LABEL,
    tooltip = "Splits table shows runs and biome splits; Timer only shows just the IGT/RTA/LrT times.",
}
local COLUMNS_ROW = { label = COLUMNS_LABEL }
local PAGE_SIZE_ROW = {
    label = PAGE_SIZE_LABEL,
    tooltip = "Finished runs per overlay page; the page keys (Hotkeys & Advanced) page through older ones.",
}

local function drawDisplaySection(draw, state, multi)
    draw.imgui.Spacing()
    draw.widgets.separator()
    local columnWidth = measureLabelColumn(draw.imgui, DISPLAY_LABELS)
    drawRowLabel(draw, OVERLAY_ROW, columnWidth, true)
    draw.widgets.dropdown(state.get("OverlayMode"), OVERLAY_MODE_OPTS)
    drawRowLabel(draw, COLUMNS_ROW, columnWidth, true)
    for index, option in ipairs(TIMER_MODE_OPTIONS) do
        if index > 1 then
            draw.imgui.SameLine()
        end
        draw.widgets.checkbox(state.get(option.alias), TIMER_MODE_OPTS[option.alias])
    end
    enforceVisibleTimerMode(state)
    -- The page keys' pickers are drawn by ModpackLib in the Hotkeys & Advanced tab (module.hotkeys).
    if multi then
        drawRowLabel(draw, PAGE_SIZE_ROW, columnWidth, true)
        draw.widgets.slider(state.get("PageSize"), PAGE_SIZE_OPTS)
    end
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
        if entry.status == "paused" then
            lines[index] = {
                text = ("%3d  %-10s  %s"):format(index, entry.label,
                    entry.live and "in progress" or formatCentiseconds(entry.pausedCs or 0)),
                opts = { color = STATUS_TEXT_COLORS.paused },
            }
        else
            lines[index] = {
                text = ("%3d  %-10s  IGT %s  RTA %s  LrT %s"):format(index, entry.label,
                    formatOptional(entry.sessionIgtCs), formatOptional(entry.sessionRtaCs),
                    formatOptional(entry.sessionLrtCs)),
                opts = { color = HISTORY_STATUS_COLORS[entry.status] or MUTED_TEXT_COLOR },
            }
        end
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
    local imgui = draw.imgui
    imgui.Spacing()
    -- Collapsed by default: the overlay is the primary view of a session; this is a second one.
    if imgui.CollapsingHeader ~= nil and not imgui.CollapsingHeader(HISTORY_HEADER) then
        return
    end
    draw.widgets.text("Every finished run in this session, with session totals at its end.", MUTED_TEXT_OPTS)
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

--- Recording tab: the run cockpit. Category and actions, status and rules, what the overlay
--- shows, and the session history for multi-run categories.
function module.drawRecordingTab(draw, state, actions, statusView)
    drawRecordingSection(draw, state, actions, statusView)
    local multi = readRecordingMode(state) == "multi"
    drawDisplaySection(draw, state, multi)
    if multi then
        drawHistorySection(draw, statusView)
    end
end

--- Settings tab: the selected category's rules, read-only for presets and editable for Custom.
function module.drawSettingsTab(draw, state)
    drawRulesSection(draw, state, readCategory(state))
end

function module.drawQuickContent(draw, state, actions, statusView)
    drawRecordingSection(draw, state, actions, statusView)
    drawRowLabel(draw, OVERLAY_ROW, measureLabelColumn(draw.imgui, DISPLAY_LABELS), true)
    draw.widgets.dropdown(state.get("OverlayMode"), OVERLAY_MODE_OPTS)
end

function module.attach(libModule, statusView)
    libModule.ui.tabs({
        {
            id = "recording",
            label = "Recording",
            draw = function(_, ui)
                return module.drawRecordingTab(ui.draw, ui.data, ui.actions, statusView)
            end,
        },
        {
            id = "settings",
            label = "Settings",
            draw = function(_, ui)
                return module.drawSettingsTab(ui.draw, ui.data)
            end,
        },
    })
    libModule.ui.quickContent(function(_, ui)
        return module.drawQuickContent(ui.draw, ui.data, ui.actions, statusView)
    end)
end

return module
