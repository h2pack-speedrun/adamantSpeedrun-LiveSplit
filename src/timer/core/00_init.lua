local deps = ...
local getTime = deps.getTime

local RtaTimer = import('timer/core/rta_timer.lua', nil, {
    getTime = getTime,
})
local LrtTimer = import('timer/core/lrt_timer.lua', nil, {
    getTime = getTime,
})
local IgtTimer = import('timer/core/igt_timer.lua', nil, {
    getCurrentRun = deps.getCurrentRun,
})
local timeUnits = import('timer/core/time_units.lua')

return {
    RtaTimer = RtaTimer,
    LrtTimer = LrtTimer,
    IgtTimer = IgtTimer,
    toCentiseconds = timeUnits.toCentiseconds,
}
