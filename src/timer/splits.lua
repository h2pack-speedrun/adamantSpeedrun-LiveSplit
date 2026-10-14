local deps = ...
local toCentiseconds = deps.toCentiseconds
local isRunSuccess = deps.isRunSuccess
local routeOf = deps.routeOf

local ROUTES = {
    underworld = { "F", "G", "H", "I" },
    surface = { "N", "O", "P", "Q" },
}

local BIOME_LABELS = {
    F = "Erebus",
    G = "Oceanus",
    H = "Fields",
    I = "Tartarus",
    N = "Ephyra",
    O = "Thessaly",
    P = "Olympus",
    Q = "Summit",
}

local EMPTY_ROUTE = {}
local EMPTY_SNAPSHOT = {}
local splits = {}
local state = {
    started = false,
    active = false,
    failed = false,
    completed = false,
    routeType = nil,
    route = nil,
    captured = {},
    currentIndex = nil,
    currentBiome = nil,
}
local rows = {
    header = {
        label = "Biome",
        igt = "IGT",
        rta = "RTA",
        lrt = "LrT",
    },
    biomes = {
        { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
        { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
        { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
        { label = "", igtCs = nil, rtaCs = nil, lrtCs = nil },
    },
    total = {
        label = "Total",
        igtCs = 0,
        rtaCs = 0,
        lrtCs = 0,
    },
}

local function cloneRoute(route)
    local cloned = {}
    for index, biome in ipairs(route or {}) do
        cloned[index] = biome
    end
    return cloned
end

local function clearRow(row)
    row.label = ""
    row.igtCs = nil
    row.rtaCs = nil
    row.lrtCs = nil
end

local function clearRows()
    rows.header.label = "Biome"
    rows.header.igt = "IGT"
    rows.header.rta = "RTA"
    rows.header.lrt = "LrT"
    for _, row in ipairs(rows.biomes) do
        clearRow(row)
    end
    rows.total.label = "Total"
    rows.total.igtCs = 0
    rows.total.rtaCs = 0
    rows.total.lrtCs = 0
end

local function detectRoute(run)
    local routeType = routeOf(run)
    if routeType == "dream" then
        return routeType, {}
    end
    return routeType, routeType and cloneRoute(ROUTES[routeType]) or nil
end

local function timeCs(value)
    if value == nil then
        return nil
    end
    return toCentiseconds(value)
end

local function captureTime(timer, mode)
    if not timer then
        return 0
    end
    if mode == "igt" then
        return timer:getInGameTime()
    end
    if mode == "rta" then
        return timer:getRealTime()
    end
    if mode == "lrt" then
        return timer:getLoadRemovedTime()
    end
    return 0
end

local function snapshotValue(snapshot, timer, mode)
    snapshot = snapshot or EMPTY_SNAPSHOT
    local key = mode .. "Cs"
    if snapshot[key] ~= nil then
        return snapshot[key]
    end
    return timeCs(captureTime(timer, mode))
end

local function getCurrentBiome(run)
    return run and run.CurrentRoom and run.CurrentRoom.RoomSetName
end

local function getRoute(run)
    if state.routeType == "dream" then
        return run and run.BiomeVisitOrder or EMPTY_ROUTE
    end
    return state.route or EMPTY_ROUTE
end

local function isCurrentBiome(run, route, index, biome)
    if getCurrentBiome(run) == biome then
        return true
    end
    return route[index] == biome and run and run.EnteredBiomes == index
end

local function getCurrentRouteIndex(run, route)
    local currentBiome = getCurrentBiome(run)
    for index, biome in ipairs(route or EMPTY_ROUTE) do
        if currentBiome == biome or route[index] == biome and run and run.EnteredBiomes == index then
            return index, biome
        end
    end
    return nil, currentBiome
end

local function setRow(row, label, igtCs, rtaCs, lrtCs)
    row.label = label or ""
    row.igtCs = igtCs
    row.rtaCs = rtaCs
    row.lrtCs = lrtCs
    return row
end

local function setSnapshotRow(row, label, snapshot, timer)
    return setRow(row, label,
        snapshotValue(snapshot, timer, "igt"),
        snapshotValue(snapshot, timer, "rta"),
        snapshotValue(snapshot, timer, "lrt"))
end

local function setCapturedRow(row, label, captured)
    return setRow(row, label,
        captured and captured.igtCs,
        captured and captured.rtaCs,
        captured and captured.lrtCs)
end

local function updateBiomeRow(row, index, timer, run, route, snapshot)
    local biome = route[index]
    if not biome then
        return setRow(row, "", nil, nil, nil)
    end

    local label = BIOME_LABELS[biome] or biome
    local captured = state.captured[biome]
    if captured then
        return setCapturedRow(row, label, captured)
    end
    if isCurrentBiome(run, route, index, biome) then
        return setSnapshotRow(row, label, snapshot, timer)
    end
    return setRow(row, label, nil, nil, nil)
end

function splits.startRun(run)
    if not state.started then
        return false
    end

    local routeType, route = detectRoute(run)
    if routeType == nil then
        return false
    end

    state.active = true
    state.failed = false
    state.completed = false
    state.routeType = routeType
    state.route = route
    state.captured = {}
    state.currentIndex = nil
    state.currentBiome = nil
    clearRows()
    return true
end

-- Starts capturing a run that was already underway when recording was armed.
function splits.adoptRun(run)
    if state.routeType == nil then
        return splits.startRun(run)
    end
    return false
end

-- Stops arming new runs while keeping the recorded rows and result visible.
function splits.disarm()
    state.started = false
end

function splits.recordCompletedBiomes(timer, run, snapshot)
    if not state.active then
        return false
    end
    if not (timer and run and run.BiomeVisitOrder) then
        return false
    end

    local changed = false
    for _, biome in ipairs(run.BiomeVisitOrder) do
        local biomeGameplayTime = run.BiomeGameplayTimes and run.BiomeGameplayTimes[biome]
        if biomeGameplayTime ~= nil and state.captured[biome] == nil then
            local rta = snapshotValue(snapshot, timer, "rta")
            local lrt = snapshotValue(snapshot, timer, "lrt")
            state.captured[biome] = {
                igtCs = timeCs(biomeGameplayTime),
                rtaCs = rta,
                lrtCs = lrt,
            }
            changed = true
        end
    end
    return changed
end

function splits.updateRows(timer, run, snapshot)
    local route = getRoute(run)
    snapshot = snapshot or EMPTY_SNAPSHOT
    for index = 1, 4 do
        updateBiomeRow(rows.biomes[index], index, timer, run, route, snapshot)
    end
    setSnapshotRow(rows.total, "Total", snapshot, timer)
    state.currentIndex, state.currentBiome = getCurrentRouteIndex(run, route)
end

function splits.updateLiveRows(timer, run, snapshot)
    local route = getRoute(run)
    local currentIndex, currentBiome = getCurrentRouteIndex(run, route)
    if currentIndex ~= state.currentIndex or currentBiome ~= state.currentBiome then
        splits.updateRows(timer, run, snapshot)
        return true
    end

    if currentIndex then
        updateBiomeRow(rows.biomes[currentIndex], currentIndex, timer, run, route, snapshot)
    end
    setSnapshotRow(rows.total, "Total", snapshot, timer)
    return false
end

function splits.finalizeRun(timer, run, snapshot)
    if not state.active then
        return false
    end

    splits.recordCompletedBiomes(timer, run, snapshot)
    splits.updateRows(timer, run, snapshot)
    state.active = false
    state.completed = isRunSuccess(run) == true
    state.failed = not state.completed
    return true
end

function splits.clear(keepStarted)
    state.started = keepStarted == true
    state.active = false
    state.failed = false
    state.completed = false
    state.routeType = nil
    state.route = nil
    state.captured = {}
    state.currentIndex = nil
    state.currentBiome = nil
    clearRows()
end

function splits.hasDetails()
    return state.active or state.completed or state.failed
end

function splits.isStarted()
    return state.started == true
end

function splits.details()
    return rows
end

return splits
