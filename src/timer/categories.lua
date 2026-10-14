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
    custom = "Set the rules yourself.",
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

local KNOWN_KEYS = {
    none = true,
    route = true,
    weapon = true,
    aspect = true,
}

local function keyOrNone(value)
    return KNOWN_KEYS[value] and value or "none"
end

--- A category id the picker knows; anything else is Custom (also the old multi-run mode).
function categories.normalize(category)
    if categories.NAMES[category] ~= nil and category ~= categories.SINGLE then
        return category
    end
    return categories.CUSTOM
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
            label = preset.label,
            completedRun = preset.completedRun or "summary",
        }
    else
        local distinct = keyOrNone(data.read("CustomDistinct"))
        settings = {
            runs = data.read("BatchTargetRuns"),
            distinct = distinct,
            same = keyOrNone(data.read("CustomSame")),
            onDeath = data.read("CustomOnDeath") == "continue" and "continue" or "reset",
            label = distinct ~= "none" and distinct or "index",
            completedRun = "summary",
        }
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
    return {
        category = category,
        runs = saved.runs,
        distinct = distinct,
        same = keyOrNone(saved.same),
        onDeath = saved.onDeath == "continue" and "continue" or "reset",
        label = distinct ~= "none" and distinct or "index",
        completedRun = "summary",
    }
end

--- Whether two settings describe the same rules.
function categories.sameRules(left, right)
    return left.category == right.category
        and left.runs == right.runs
        and left.distinct == right.distinct
        and left.same == right.same
        and left.onDeath == right.onDeath
end

return categories
