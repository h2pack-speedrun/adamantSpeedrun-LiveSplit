-- Run keys used by category rules and labels. Phase 1 resolves the route only;
-- weapon and aspect resolvers arrive with the category presets.

local keys = {}

local SURFACE_BIOMES = {
    N = true,
    O = true,
    P = true,
    Q = true,
}

--- "dream", "surface" or "underworld"; nil when there is no run.
function keys.routeOf(run)
    if not run then
        return nil
    end
    if run.IsDreamRun then
        return "dream"
    end
    local currentRoomSet = run.CurrentRoom and run.CurrentRoom.RoomSetName
    if SURFACE_BIOMES[currentRoomSet] or run.BiomesReached and run.BiomesReached.N then
        return "surface"
    end
    return "underworld"
end

function keys.resolve(run)
    return {
        route = keys.routeOf(run),
    }
end

return keys
