-- luacheck: read globals GameState
-- Game reads used by the timer: the real-time clock, the current run, run success, and run
-- history for reconciling a saved session after a restart.
local function isRunSuccess(run)
    if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
        return WasRunSuccess(run) == true
    end
    return run and run.Cleared == true
end

return {
    getTime = GetTime,
    getCurrentRun = function()
        return rom and rom.game and rom.game.CurrentRun or CurrentRun
    end,
    isRunSuccess = isRunSuccess,
    --- Finished runs in the loaded save, which is also the ordinal of the run now starting.
    --- nil before a save is loaded.
    currentRunOrdinal = function()
        local gameState = rom and rom.game and rom.game.GameState or GameState
        if type(gameState) ~= "table" then
            return nil
        end
        if gameState.CompletedRunsCache ~= nil then
            return gameState.CompletedRunsCache
        end
        return gameState.RunHistory and #gameState.RunHistory or 0
    end,
    --- Result of the run with `ordinal`, read from run history once it has finished.
    findRunResult = function(ordinal)
        local gameState = rom and rom.game and rom.game.GameState or GameState
        local history = type(gameState) == "table" and gameState.RunHistory or nil
        local run = history and history[ordinal + 1] or nil
        if run == nil then
            return nil
        end
        return {
            cleared = isRunSuccess(run) == true,
            igtSeconds = run.GameplayTime or 0,
        }
    end,
}
