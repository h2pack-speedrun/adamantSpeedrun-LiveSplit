-- Real-Time Attack timer. Reads the system clock on every query.
--
-- The game does not track real time, and _worldTime is time-scaled (slow-motion, hitstop) and
-- stalls during pauses and loads, so RTA never advances on it.

local deps = ...
local getTime = deps.getTime

local RtaTimer = {}

function RtaTimer:new()
    local o = {
        Running = false,
        StartingSystemTime = nil,
        ElapsedTime = 0,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Starts timing, optionally continuing from `elapsedSeconds` already recorded (a resumed session).
function RtaTimer:start(elapsedSeconds)
    self.StartingSystemTime = getTime({}) - (elapsedSeconds or 0)
    self.ElapsedTime = elapsedSeconds or 0
    self.Running = true
end

function RtaTimer:stop()
    if self.Running then
        self.ElapsedTime = getTime({}) - self.StartingSystemTime
    end
    self.Running = false
end

function RtaTimer:getTime()
    if self.Running then
        return getTime({}) - self.StartingSystemTime
    end
    return self.ElapsedTime
end

return RtaTimer
