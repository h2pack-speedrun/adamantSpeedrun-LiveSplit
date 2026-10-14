-- In-Game Time timer. Polls the game's CurrentRun.GameplayTime.

local deps = ...
local getCurrentRun = deps and deps.getCurrentRun or nil

local IgtTimer = {}

function IgtTimer:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function IgtTimer:getTime()  --luacheck: ignore 212
    local currentRun = getCurrentRun and getCurrentRun() or rom and rom.game and rom.game.CurrentRun or CurrentRun
    if not currentRun or currentRun.GameplayTime == nil then
        return 0
    end
    return currentRun.GameplayTime
end

return IgtTimer
