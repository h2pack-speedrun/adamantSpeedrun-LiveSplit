-- Multi-run categories: the five presets and the custom (advanced) category, resolved into session
-- settings. See docs/CATEGORIES_DESIGN.md.

local categories = {}

categories.SINGLE = "single"
categories.CUSTOM = "custom"

-- Picker order: Single Run first, then the presets, then Custom.
categories.ORDER = { "single", "allRegions", "threeWeapons", "oneWeapon", "allWeapons", "allAspects", "custom" }

categories.NAMES = {
    single = "Single Run",
    allRegions = "All Regions",
    threeWeapons = "3 Weapons",
    oneWeapon = "One Weapon",
    allWeapons = "All Weapons",
    allAspects = "All Aspects",
    custom = "Custom",
}

categories.RULES_TEXT = {
    single = "Records each run's biome splits.",
    allRegions = "Clear the Underworld and the Surface, in either order, with the same aspect.",
    threeWeapons = "Clear a run with 3 different weapons, any order and any region.",
    oneWeapon = "Clear a run with each of one weapon's 4 aspects, any order and any region.",
    allWeapons = "Clear a run with each of the 6 weapons, any order and any region.",
    allAspects = "Clear a run with each of the 24 aspects, any order and any region.",
}

-- Rule keys selectable for a custom category.
categories.KEY_VALUES = { "none", "route", "weapon", "aspect" }
categories.KEY_NAMES = {
    none = "None",
    route = "Region",
    weapon = "Weapon",
    aspect = "Aspect",
}
categories.ON_DEATH_VALUES = { "continue", "reset" }
categories.ON_DEATH_NAMES = {
    continue = "Log and continue",
    reset = "End the session",
}

local PRESETS = {
    allRegions = {
        runs = 2,
        distinct = "route",
        allowed = { underworld = true, surface = true },
        same = "aspect",
        label = "route",
        completedRun = "splits",
    },
    threeWeapons = { runs = 3, distinct = "weapon", same = "none", label = "weapon" },
    oneWeapon = { runs = 4, distinct = "aspect", same = "weapon", label = "aspect" },
    allWeapons = { runs = 6, distinct = "weapon", same = "none", label = "weapon" },
    allAspects = { runs = 24, distinct = "aspect", same = "none", label = "aspect" },
}

-- Regions a Custom session can limit "each run needs a new region" to.
categories.REGIONS = {
    { value = "underworld", name = "Underworld", alias = "CustomAllowUnderworld" },
    { value = "surface", name = "Surface", alias = "CustomAllowSurface" },
    { value = "dream", name = "Dream Dives", alias = "CustomAllowDream" },
}

local KNOWN_KEYS = {
    none = true,
    route = true,
    weapon = true,
    aspect = true,
}

local function keyOrNone(value)
    return KNOWN_KEYS[value] and value or "none"
end

-- How many values each key can take (timer/keys.lua; a test keeps these in step).
categories.WEAPON_COUNT = 6
categories.ASPECT_COUNT = 24
categories.ASPECTS_PER_WEAPON = 4

local function allowedCount(allowed)
    if allowed == nil then
        return #categories.REGIONS
    end
    local count = 0
    for _, region in ipairs(categories.REGIONS) do
        if allowed[region.value] == true then
            count = count + 1
        end
    end
    return count
end

--- Whether every run can keep the same `same` while each needs a new `distinct`. An aspect belongs
--- to one weapon, so a fixed aspect also fixes the weapon.
function categories.compatibleSame(distinct, same)
    if distinct == "none" or same == "none" then
        return true
    end
    if distinct == same then
        return false
    end
    return not (distinct == "weapon" and same == "aspect")
end

--- Most runs a session can count: each needs a new `distinct`, so there are only so many. Nil when
--- any number can count.
function categories.maxRuns(distinct, same, allowed)
    if distinct == "route" then
        return allowedCount(allowed)
    elseif distinct == "weapon" then
        return categories.WEAPON_COUNT
    elseif distinct == "aspect" then
        return same == "weapon" and categories.ASPECTS_PER_WEAPON or categories.ASPECT_COUNT
    end
    return nil
end

-- Custom rules that can always finish: an incompatible `same` becomes "none" and the run count is
-- capped at what the `distinct` key allows.
local function finishable(settings)
    if not categories.compatibleSame(settings.distinct, settings.same) then
        settings.same = "none"
    end
    local maxRuns = categories.maxRuns(settings.distinct, settings.same, settings.allowed)
    if maxRuns ~= nil and settings.runs > maxRuns then
        settings.runs = maxRuns
    end
    return settings
end

local function labelFor(distinct)
    return distinct ~= "none" and distinct or "index"
end

--- Allowed regions, or nil when every region is allowed (or, as a fallback, none is).
local function allowedOrNil(allowed)
    if allowed == nil then
        return nil
    end
    local count = allowedCount(allowed)
    if count == 0 or count == #categories.REGIONS then
        return nil
    end
    return allowed
end

local function customAllowed(data, distinct)
    if distinct ~= "route" then
        return nil
    end
    local allowed = {}
    for _, region in ipairs(categories.REGIONS) do
        allowed[region.value] = data.read(region.alias) ~= false or nil
    end
    return allowedOrNil(allowed)
end

--- A category id the picker knows; anything else is Custom (also the old multi-run mode).
function categories.normalize(category)
    if categories.NAMES[category] ~= nil and category ~= categories.SINGLE then
        return category
    end
    return categories.CUSTOM
end

function categories.isPreset(category)
    return PRESETS[category] ~= nil
end

--- Session settings for a multi-run category. Presets fix their rules (deaths are logged and the
--- session continues); Custom reads its rules from module data.
function categories.settingsFor(category, data)
    category = categories.normalize(category)
    local preset = PRESETS[category]
    local settings
    if preset ~= nil then
        settings = {
            runs = preset.runs,
            distinct = preset.distinct,
            same = preset.same,
            allowed = preset.allowed,
            onDeath = "continue",
            -- Presets always survive a game exit or crash.
            resumeAfterRestart = true,
            label = preset.label,
            completedRun = preset.completedRun or "summary",
        }
    else
        local distinct = keyOrNone(data.read("CustomDistinct"))
        settings = finishable({
            runs = data.read("BatchTargetRuns"),
            distinct = distinct,
            same = keyOrNone(data.read("CustomSame")),
            allowed = customAllowed(data, distinct),
            onDeath = data.read("CustomOnDeath") == "continue" and "continue" or "reset",
            resumeAfterRestart = data.read("ResumeAfterRestart") == true,
            label = labelFor(distinct),
            completedRun = data.read("CustomKeepSplits") == true and "splits" or "summary",
        })
    end
    settings.category = category
    return settings
end

--- Settings saved with a session and restored with it, so a resumed session keeps its rules.
function categories.settingsFromSaved(saved)
    local category = categories.normalize(saved.category)
    if PRESETS[category] ~= nil then
        return categories.settingsFor(category)
    end
    local distinct = keyOrNone(saved.distinct)
    return finishable({
        category = category,
        runs = saved.runs,
        distinct = distinct,
        same = keyOrNone(saved.same),
        allowed = distinct == "route" and allowedOrNil(saved.allowed) or nil,
        onDeath = saved.onDeath == "continue" and "continue" or "reset",
        label = labelFor(distinct),
        completedRun = saved.completedRun == "splits" and "splits" or "summary",
    })
end

--- Writes a preset's rules into Custom's settings, so Custom starts from that preset.
function categories.copyToCustom(category, data)
    local settings = categories.settingsFor(category)
    data.write("BatchTargetRuns", settings.runs)
    data.write("CustomDistinct", settings.distinct)
    data.write("CustomSame", settings.same)
    data.write("CustomOnDeath", settings.onDeath)
    for _, region in ipairs(categories.REGIONS) do
        data.write(region.alias, settings.allowed == nil or settings.allowed[region.value] == true)
    end
    data.write("CustomKeepSplits", settings.completedRun == "splits")
    data.write("ResumeAfterRestart", settings.resumeAfterRestart)
end

--- Display text for allowed regions: "Underworld or Surface", or nil when any region counts.
function categories.allowedText(allowed)
    if allowed == nil then
        return nil
    end
    local names = {}
    for _, region in ipairs(categories.REGIONS) do
        if allowed[region.value] then
            names[#names + 1] = region.name
        end
    end
    return table.concat(names, " or ")
end

--- One-line summary of a category's rules, shown under the recording status.
function categories.summary(settings)
    local parts = { ("%d %s"):format(settings.runs, settings.runs == 1 and "run" or "runs") }
    if settings.distinct ~= "none" then
        local text = "each a new " .. categories.KEY_NAMES[settings.distinct]:lower()
        local allowed = categories.allowedText(settings.allowed)
        if allowed ~= nil then
            text = text .. " (" .. allowed .. ")"
        end
        parts[#parts + 1] = text
    end
    if settings.same ~= "none" then
        parts[#parts + 1] = "same " .. categories.KEY_NAMES[settings.same]:lower()
    end
    parts[#parts + 1] = settings.onDeath == "continue" and "deaths logged" or "death ends session"
    if settings.completedRun == "splits" then
        parts[#parts + 1] = "biome splits kept"
    end
    return table.concat(parts, ", ")
end

local function sameAllowed(left, right)
    if left == nil or right == nil then
        return left == right
    end
    for _, region in ipairs(categories.REGIONS) do
        if (left[region.value] == true) ~= (right[region.value] == true) then
            return false
        end
    end
    return true
end

--- Whether two settings describe the same rules.
function categories.sameRules(left, right)
    return left.category == right.category
        and left.runs == right.runs
        and left.distinct == right.distinct
        and left.same == right.same
        and left.onDeath == right.onDeath
        and left.completedRun == right.completedRun
        and sameAllowed(left.allowed, right.allowed)
end

return categories
