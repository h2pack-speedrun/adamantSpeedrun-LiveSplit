local singleRun = ...

local hooksAdapter = {}

local function isEnabled(callbacks, host)
    return callbacks.isEnabled(host) == true
end

local function emitDisplayStarted(callbacks, runtime)
    callbacks.onDisplayLoopStarted(runtime)
    callbacks.onDisplayChanged(runtime)
end

function hooksAdapter.installHooks(hooks, callbacks)
    hooks.wrap("StartNewRun", function(host, runtime, baseFunc, prevRun, args)
        if not isEnabled(callbacks, host) then
            return baseFunc(prevRun, args)
        end

        singleRun.beginRun()
        local run = baseFunc(prevRun, args)
        callbacks.onRunStarted(runtime)
        callbacks.onDisplayChanged(runtime)
        return run
    end)

    hooks.wrap("RoomEntranceMaterialize", function(host, runtime, baseFunc, ...)
        if not isEnabled(callbacks, host) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        if singleRun.startDisplayLoop() then
            emitDisplayStarted(callbacks, runtime)
        end
        return value
    end)

    hooks.wrap("RoomEntranceDreamBiomeStart", function(host, runtime, baseFunc, ...)
        if not isEnabled(callbacks, host) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        if singleRun.startDisplayLoop() then
            emitDisplayStarted(callbacks, runtime)
        end
        return value
    end)

    hooks.wrap("RecordRunStats", function(host, runtime, baseFunc, ...)
        if not isEnabled(callbacks, host) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        local finalized = singleRun.finalizeRun()
        if finalized then
            callbacks.onRunFinalized(runtime)
            callbacks.onDisplayChanged(runtime)
        end
        return value
    end)

    hooks.wrap("AddTimerBlock", function(host, runtime, baseFunc, currRun, timerBlockName, ...)
        -- Pass native arguments through; AddTimerBlock's args select the MapState scope.
        local value = baseFunc(currRun, timerBlockName, ...)
        if isEnabled(callbacks, host) and timerBlockName == "MapLoad" and singleRun.processLoadEvent(true) then
            callbacks.onLoadEvent(runtime, true)
        end
        return value
    end)

    hooks.wrap("RemoveTimerBlock", function(host, runtime, baseFunc, currRun, timerBlockName, ...)
        -- Pass native arguments through; AddTimerBlock's args select the MapState scope.
        local value = baseFunc(currRun, timerBlockName, ...)
        if isEnabled(callbacks, host) and timerBlockName == "MapLoad" and singleRun.processLoadEvent(false) then
            callbacks.onLoadEvent(runtime, false)
        end
        return value
    end)
end

return hooksAdapter
