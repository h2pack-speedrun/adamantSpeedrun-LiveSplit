-- In-Game Time timer. Polls the game's CurrentRun.GameplayTime.

local deps = ...
local getCurrentRun = deps.getCurrentRun

local IgtTimer = {}

function IgtTimer:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function IgtTimer:getTime()  --luacheck: ignore 212
    local currentRun = getCurrentRun()
    if not currentRun or currentRun.GameplayTime == nil then
        return 0
    end
    return currentRun.GameplayTime
end

return IgtTimer
