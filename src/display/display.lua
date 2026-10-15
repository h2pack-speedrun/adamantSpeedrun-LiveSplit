local deps = ...
local timer = deps.timer
local data = import("data.lua")
local overlay = import('display/overlay_rows.lua', nil, {
    fonts = deps.fonts,
})
local overlayEvents = deps.overlayEvents
local formatCache = import('display/format_cache.lua', nil, {
    formatCentiseconds = import('display/time_format.lua').formatCentiseconds,
})
local settings = import('display/settings.lua', nil, {
    timer = timer,
})
local projection = import('display/projection.lua', nil, {
    timer = timer,
    formatCache = formatCache,
})

local TIMER_REFRESH_INTERVAL = 0.05

local display = {
    settings = settings,
    paging = import('display/paging.lua'),
}
local displayOverlays = nil
local ensureOverlays

function display.project(ctx, opts)
    opts = opts or {}
    local runtime = opts.runtime
    projection.begin()
    display.paging.takePending()
    local adapters = ensureOverlays()
    adapters.singleRun.project(ctx, runtime)
    adapters.batch.project(ctx, runtime, opts.liveOnly == true)
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
            overlay = overlay,
            isVisible = settings.isBatchVisible,
            isModeVisible = settings.isModeVisible,
            formatCache = formatCache,
            paging = display.paging,
            readPageSize = settings.pageSize,
            maxPageSize = data.pageSize.max,
            maxBiomes = data.maxAttemptBiomes,
            currentRunDetails = timer.currentRun.detailsSnapshot,
        }),
        splits = import('display/overlay_splits.lua', nil, {
            currentRun = timer.currentRun,
            overlay = overlay,
            isVisible = settings.isSplitsTableVisible,
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
        -- A page hotkey also wakes the interval so the new page shows even with no run active.
        when = function(host)
            return overlayEvents.whenActive(host) or display.paging.isPending()
        end,
    })
end

return display
