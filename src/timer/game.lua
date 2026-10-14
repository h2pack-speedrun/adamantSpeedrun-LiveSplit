-- Game reads used by the timer: the real-time clock, the current run, and run success.
return {
    getTime = GetTime,
    getCurrentRun = function()
        return rom and rom.game and rom.game.CurrentRun or CurrentRun
    end,
    isRunSuccess = function(run)
        if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
            return WasRunSuccess(run) == true
        end
        return run and run.Cleared == true
    end,
}
