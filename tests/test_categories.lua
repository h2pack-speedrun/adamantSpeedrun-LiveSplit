local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual
local setTime = support.setTime
local keys = support.keys
local categories = support.categories

-- Keys: weapon and aspect come from the hero; names stay short for the overlay.
local staffCirceRun = {
    CurrentRoom = { RoomSetName = "F" },
    Hero = {
        Weapons = { WeaponStaffSwing = true, WeaponCastArm = true },
        TraitDictionary = { StaffClearCastAspect = {}, SomeBoon = {} },
    },
}
local resolved = keys.resolve(staffCirceRun)
assertEqual(resolved.route, "underworld")
assertEqual(resolved.weapon, "WeaponStaffSwing")
assertEqual(resolved.aspect, "StaffClearCastAspect")
assertEqual(keys.nameOf("weapon", "WeaponSuit"), "Coat")
assertEqual(keys.nameOf("aspect", "StaffClearCastAspect"), "Staff Circe")
assertEqual(keys.nameOf("aspect", "AxeRecoveryAspect"), "Axe Melinoë")
assertEqual(keys.nameOf("route", "surface"), "Surface")
assertEqual(keys.nameOf("weapon", "Nope"), nil)
assertEqual(keys.resolve({ Hero = { Weapons = {}, TraitDictionary = {} } }).weapon, nil)
local aspectCount = 0
for _, weapon in ipairs(keys.WEAPONS) do
    for _, aspect in ipairs(keys.ASPECTS[weapon]) do
        assert(keys.nameOf("aspect", aspect) ~= nil, aspect)
        aspectCount = aspectCount + 1
    end
end
assertEqual(aspectCount, 24)

-- Categories: presets fix their rules; Custom reads module data; unknown ids are Custom.
local allRegions = categories.settingsFor("allRegions")
assertEqual(allRegions.runs, 2)
assertEqual(allRegions.distinct, "route")
assertEqual(allRegions.same, "aspect")
assertEqual(allRegions.onDeath, "continue")
assertEqual(allRegions.completedRun, "splits")
assertEqual(allRegions.allowed.dream, nil)
assertEqual(categories.settingsFor("allAspects").runs, 24)
assertEqual(categories.settingsFor("oneWeapon").same, "weapon")
local customData = {
    BatchTargetRuns = 5,
    CustomDistinct = "weapon",
    CustomSame = "bogus",
    CustomOnDeath = "continue",
}
local custom = categories.settingsFor("custom", {
    read = function(alias)
        return customData[alias]
    end,
})
assertEqual(custom.runs, 5)
assertEqual(custom.distinct, "weapon")
assertEqual(custom.same, "none")
assertEqual(custom.onDeath, "continue")
assertEqual(custom.label, "weapon")
assertEqual(categories.normalize("single"), "custom")
assertEqual(categories.normalize("nonsense"), "custom")
assertEqual(categories.sameRules(custom, categories.settingsFromSaved(custom)), true)
assertEqual(categories.sameRules(custom, allRegions), false)
assertEqual(categories.settingsFromSaved({ category = "allWeapons" }).runs, 6)

-- All Weapons: labels come from weapons; deaths and repeats are logged without ending the session.
local function heroRun(weapon, aspect, roomSet, cleared)
    return {
        CurrentRoom = { RoomSetName = roomSet or "F" },
        Cleared = cleared,
        Hero = {
            Weapons = { [weapon] = true },
            TraitDictionary = { [aspect] = {} },
        },
    }
end
local function timerWithIgt(igt)
    return {
        getInGameTime = function()
            return igt
        end,
    }
end
local weaponsBatch = assert(loadfile("src/timer/batch.lua"))(support.batchDeps())
weaponsBatch.start(categories.settingsFor("allWeapons"))
local function playWeapon(batch, weapon, aspect, cleared, igt)
    local run = heroRun(weapon, aspect, "F", cleared)
    batch.startRun(keys.resolve(run), 0)
    batch.finalizeRun(timerWithIgt(igt), run)
end
setTime(0)
playWeapon(weaponsBatch, "WeaponAxe", "AxeRecoveryAspect", false, 10)
playWeapon(weaponsBatch, "WeaponAxe", "AxeRecoveryAspect", true, 20)
playWeapon(weaponsBatch, "WeaponAxe", "AxeArmCastAspect", true, 20)
weaponsBatch.startRun(keys.resolve(heroRun("WeaponLob", "LobGunAspect")), 0)
local weaponRows = weaponsBatch.session(timerWithIgt(5))
assertEqual(weaponRows.title, "All Weapons")
assertEqual(weaponRows.completedRuns, 1)
assertEqual(weaponRows.targetRuns, 6)
assertEqual(weaponRows.failedCount, 1)
assertEqual(weaponRows.groups[1].heading.label, "Axe (died)")
assertEqual(weaponRows.groups[2].heading.label, "Axe")
assertEqual(weaponRows.groups[3].heading.label, "Axe (repeat)")
assertEqual(weaponRows.current.heading.label, "Current: Skull")
assertEqual(weaponRows.splits, false)
assertEqual(weaponsBatch.status().text, "Recording 1 / 6")
assertEqual(weaponsBatch.history()[1].label, "Axe (died)")

-- All Regions: biome splits are kept per attempt with session-cumulative times; a dream run and a
-- different aspect never count.
local regionsBatch = assert(loadfile("src/timer/batch.lua"))(support.batchDeps())
regionsBatch.start(categories.settingsFor("allRegions"))
setTime(0)
local underworld = heroRun("WeaponStaffSwing", "StaffClearCastAspect", "F")
regionsBatch.startRun(keys.resolve(underworld), 0)
setTime(100)
underworld.BiomeVisitOrder = { "F" }
underworld.BiomeGameplayTimes = { F = 90 }
underworld.CurrentRoom = { RoomSetName = "G" }
assertEqual(regionsBatch.captureBiomes(underworld), true)
assertEqual(regionsBatch.captureBiomes(underworld), false)
local liveRows = regionsBatch.session(timerWithIgt(95), underworld)
assertEqual(liveRows.splits, true)
assertEqual(liveRows.current.heading.label, "Current: Underworld")
assertEqual(liveRows.current.biomeCount, 4)
assertEqual(liveRows.current.biomes[1].label, "Erebus")
assertEqual(liveRows.current.biomes[1].igtCs, 9000)
assertEqual(liveRows.current.biomes[1].rtaCs, 10000)
assertEqual(liveRows.current.biomes[2].label, "Oceanus")
assertEqual(liveRows.current.biomes[2].rtaCs, 10000)
assertEqual(liveRows.current.biomes[3].igtCs, nil)
setTime(400)
underworld.Cleared = true
underworld.BiomeVisitOrder = { "F", "G", "H", "I" }
underworld.BiomeGameplayTimes = { F = 90, G = 180, H = 270, I = 360 }
regionsBatch.finalizeRun(timerWithIgt(360), underworld)
local dream = heroRun("WeaponStaffSwing", "StaffClearCastAspect", "F", true)
dream.IsDreamRun = true
regionsBatch.startRun(keys.resolve(dream), 1)
regionsBatch.finalizeRun(timerWithIgt(10), dream)
local otherAspect = heroRun("WeaponStaffSwing", "BaseStaffAspect", "N", true)
regionsBatch.startRun(keys.resolve(otherAspect), 2)
regionsBatch.finalizeRun(timerWithIgt(10), otherAspect)
setTime(500)
local surface = heroRun("WeaponStaffSwing", "StaffClearCastAspect", "N")
regionsBatch.startRun(keys.resolve(surface), 3)
setTime(600)
surface.BiomeVisitOrder = { "N" }
surface.BiomeGameplayTimes = { N = 80 }
regionsBatch.captureBiomes(surface)
local regionRows = regionsBatch.session(timerWithIgt(85), surface)
assertEqual(regionRows.groups[1].heading.label, "Underworld")
assertEqual(regionRows.groups[1].biomeCount, 4)
assertEqual(regionRows.groups[1].biomes[4].label, "Tartarus")
assertEqual(regionRows.groups[1].biomes[4].igtCs, 36000)
assertEqual(regionRows.groups[2].heading.label, "Dream (invalid)")
assertEqual(regionRows.groups[3].heading.label, "Surface (invalid)")
assertEqual(regionRows.current.biomes[1].label, "Ephyra")
-- Surface splits continue the session clock after the underworld run and the invalid runs.
assertEqual(regionRows.current.biomes[1].igtCs, 36000 + 1000 + 1000 + 8000)
assertEqual(regionRows.current.biomes[1].rtaCs, 60000)
setTime(700)
surface.Cleared = true
regionsBatch.finalizeRun(timerWithIgt(170), surface)
assertEqual(regionsBatch.status().text, "Recorded 2 / 2")
assertEqual(regionsBatch.session().completedRuns, 2)

-- Rules and biome splits survive a save and restore.
local saved = {}
local status = support.newRuntimeState(saved)
local session = regionsBatch.getSession()
local record = session:toRecord()
for index = 1, #record.attempts do
    support.store.saveAttempt(status, record, index)
end
support.store.saveTotals(status, record, regionsBatch.getSettings())
local loaded, rules = support.store.load(status)
local restoredSettings = categories.settingsFromSaved(rules)
assertEqual(restoredSettings.category, "allRegions")
assertEqual(restoredSettings.completedRun, "splits")
local restored = support.Session.restore(restoredSettings, loaded)
assertEqual(#restored:getAttempts()[1].biomes, 4)
assertEqual(restored:getAttempts()[1].biomes[4].code, "I")
assertEqual(restored:getAttempts()[1].biomes[4].igtCs, 36000)
assertEqual(restored:getOutcome(), "completed")
setTime(0)

-- Recording: changing the category applies at once until the session has progress.
local recordingData = {
    RecordingMode = "multi",
    Category = "allWeapons",
    ResumeAfterRestart = true,
}
local recordingRuntime = {
    data = {
        read = function(alias)
            return recordingData[alias]
        end,
    },
    status = support.newRuntimeState({}),
}
local recordingBatch = assert(loadfile("src/timer/batch.lua"))(support.batchDeps())
local recordingSplits = assert(loadfile("src/timer/splits.lua"))({
    keys = support.keys,
    toCentiseconds = support.core.toCentiseconds,
    isRunSuccess = support.isRunSuccess,
})
local recording = assert(loadfile("src/timer/recording.lua"))(support.recordingDeps({
    splits = recordingSplits,
    batch = recordingBatch,
}))
recording.initialize(recordingRuntime)
recording.start(recordingRuntime)
assertEqual(recording.status().text, "Recording ready for 6 runs")
recordingData.Category = "threeWeapons"
recording.syncSettings(recordingRuntime)
assertEqual(recording.status().text, "Recording ready for 3 runs")
recording.onRunStarted(recordingRuntime, heroRun("WeaponAxe", "AxeRecoveryAspect"))
recordingData.Category = "allAspects"
recording.syncSettings(recordingRuntime)
assertEqual(recordingBatch.getSettings().category, "threeWeapons")
recording.start(recordingRuntime)
assertEqual(recordingBatch.getSettings().category, "allAspects")
assertEqual(recording.status().text, "Recording ready for 24 runs")
recording.stop(recordingRuntime)

-- UI picker: an old multi-run setup moves to Custom once; Single Run afterwards sticks.
local uiModule = support.withImport(function()
    return assert(loadfile("src/ui.lua"))()
end)
local uiValues = {
    RecordingMode = "multi",
    Category = "single",
    CategoryVersion = 0,
}
local texts = {}
local uiDraw = {
    imgui = { SameLine = function() end, Spacing = function() end },
    widgets = {
        text = function(text)
            texts[#texts + 1] = text
        end,
        separator = function() end,
        checkbox = function() return false end,
        stepper = function() return false end,
        dropdown = function() return false end,
        button = function(_, opts)
            opts.action:stage(opts.value)
            return true
        end,
    },
}
local uiState = {
    get = function(alias)
        return { alias = alias }
    end,
    read = function(alias)
        return uiValues[alias]
    end,
    write = function(alias, value)
        uiValues[alias] = value
    end,
}
local uiActions = {
    get = function()
        return { stage = function() end }
    end,
}
local uiView = {
    getRecordingStatus = function()
        return { kind = "idle", text = "Not recording" }
    end,
    getSessionHistory = function()
        return {}
    end,
}
uiModule.drawQuickContent(uiDraw, uiState, uiActions, uiView)
assertEqual(uiValues.Category, "custom")
assertEqual(uiValues.CategoryVersion, 1)
assertEqual(uiValues.RecordingMode, "multi")
uiValues.Category = "single"
uiModule.drawQuickContent(uiDraw, uiState, uiActions, uiView)
assertEqual(uiValues.Category, "single")
assertEqual(uiValues.RecordingMode, "single")
uiValues.Category = "allRegions"
texts = {}
uiModule.drawQuickContent(uiDraw, uiState, uiActions, uiView)
assertEqual(uiValues.RecordingMode, "multi")
local sawRules = false
for _, text in ipairs(texts) do
    if text == categories.RULES_TEXT.allRegions then
        sawRules = true
    end
end
assert(sawRules, "expected the All Regions rules line")
