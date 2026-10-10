local deps = ... or {}
local timer = deps.timer
local data = deps.data or import("data.lua")
local overlay = deps.overlay or import('display/overlay_rows.lua', nil, {
    fonts = deps.fonts,
})
local overlayEvents = deps.overlayEvents
local timeFormat = deps.timeFormat or import('display/time_format.lua')
local formatCentiseconds = deps.formatCentiseconds or timeFormat.formatCentiseconds
local formatCache = deps.formatCache or import('display/format_cache.lua', nil, {
    formatCentiseconds = formatCentiseconds,
})
local settings = deps.settings or import('display/settings.lua', nil, {
    timer = timer,
})
local projection = deps.projection or import('display/projection.lua', nil, {
    timer = timer,
    formatCache = formatCache,
})

local TIMER_REFRESH_INTERVAL = 0.05

local display = {
    settings = settings,
}
local displayOverlays = nil
local ensureOverlays

function display.project(ctx, opts)
    opts = opts or {}
    local runtime = opts.runtime
    projection.begin()
    local adapters = ensureOverlays()
    adapters.singleRun.project(ctx, runtime)
    adapters.batch.project(ctx, runtime)
    adapters.splits.project(ctx, runtime, opts.liveOnly == true)
    ctx.refreshOwned()
end

function ensureOverlays()
    if displayOverlays then
        return displayOverlays
    end

    displayOverlays = {
        singleRun = import('display/overlay_single_run.lua', nil, {
            overlay = overlay,
            isModeVisible = settings.isModeVisible,
            isTimerDisplayVisible = settings.isTimerDisplayVisible,
            getDisplayTime = projection.displayTime,
        }),
        batch = import('display/overlay_batch.lua', nil, {
            batch = {
                hasSession = timer.batch.hasSession,
                session = projection.batchSession,
            },
            maxRows = data.batchTargetRuns.max,
            overlay = overlay,
            isVisible = settings.isBatchVisible,
            isModeVisible = settings.isModeVisible,
            formatCache = formatCache,
        }),
        splits = import('display/overlay_splits.lua', nil, {
            currentRun = timer.currentRun,
            overlay = overlay,
            isVisible = settings.isRecordingTableVisible,
            isModeVisible = settings.isModeVisible,
            formatCache = formatCache,
        }),
    }
    return displayOverlays
end

function display.registerOverlays(overlays)
    local adapters = ensureOverlays()
    local timerOverlayOrder = overlays.order.module + 10
    local batchOverlayOrder = timerOverlayOrder + 10
    local splitOverlayOrder = batchOverlayOrder + 20

    adapters.singleRun.register(overlays, timerOverlayOrder)
    adapters.batch.register(overlays, batchOverlayOrder)
    adapters.splits.register(overlays, splitOverlayOrder)

    overlays.onCommit(function(host, runtime, ctx)
        overlayEvents.onCommit(host, runtime, ctx, display)
    end)

    overlays.onInterval("timer", TIMER_REFRESH_INTERVAL, function(host, runtime, ctx)
        overlayEvents.onInterval(host, runtime, ctx, display)
    end, {
        when = overlayEvents.whenActive,
    })
end

return display
