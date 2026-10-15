-- Session pause key, requested from ModpackLib's hotkeys capability. A pause only takes effect
-- between runs of a multi-run session; elsewhere the press does nothing.

local deps = ...
local pauseKey = deps.pauseKey
local togglePause = deps.togglePause

local pauseHotkey = {}

function pauseHotkey.attach(module)
    module.hotkeys.request(pauseKey.id, {
        label = "Pause session",
        default = pauseKey.default,
        alias = pauseKey.alias,
        tooltip = "Pauses or resumes a multi-run session between runs, for breaks in long sessions. "
            .. "The session clocks stop and the overlay shows a Paused split; starting a run resumes.",
        onPress = togglePause,
    })
end

return pauseHotkey
