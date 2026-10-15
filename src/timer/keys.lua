-- Run keys used by category rules and labels: route, weapon and aspect, plus their display names.
-- Weapon and aspect ids follow the game's WeaponSets.HeroPrimaryWeapons and
-- WeaponUpgradeData.DisplayOrder; names are the English TraitText display names.

local keys = {}

keys.ROUTES = {
    underworld = { "F", "G", "H", "I" },
    surface = { "N", "O", "P", "Q" },
}

keys.BIOME_NAMES = {
    F = "Erebus",
    G = "Oceanus",
    H = "Fields",
    I = "Tartarus",
    N = "Ephyra",
    O = "Thessaly",
    P = "Olympus",
    Q = "Summit",
}

keys.ROUTE_NAMES = {
    underworld = "Underworld",
    surface = "Surface",
    dream = "Dream",
}

keys.WEAPONS = {
    "WeaponStaffSwing",
    "WeaponDagger",
    "WeaponTorch",
    "WeaponAxe",
    "WeaponLob",
    "WeaponSuit",
}

-- Short names keep overlay labels narrow.
keys.WEAPON_NAMES = {
    WeaponStaffSwing = "Staff",
    WeaponDagger = "Blades",
    WeaponTorch = "Flames",
    WeaponAxe = "Axe",
    WeaponLob = "Skull",
    WeaponSuit = "Coat",
}

keys.ASPECTS = {
    WeaponStaffSwing = { "BaseStaffAspect", "StaffClearCastAspect", "StaffSelfHitAspect", "StaffRaiseDeadAspect" },
    WeaponDagger = { "DaggerBackstabAspect", "DaggerBlockAspect", "DaggerHomingThrowAspect", "DaggerTripleAspect" },
    WeaponTorch = { "TorchSpecialDurationAspect", "TorchDetonateAspect", "TorchSprintRecallAspect",
        "TorchAutofireAspect" },
    WeaponAxe = { "AxeRecoveryAspect", "AxeArmCastAspect", "AxePerfectCriticalAspect", "AxeRallyAspect" },
    WeaponLob = { "LobAmmoBoostAspect", "LobCloseAttackAspect", "LobImpulseAspect", "LobGunAspect" },
    WeaponSuit = { "BaseSuitAspect", "SuitHexAspect", "SuitMarkCritAspect", "SuitComboAspect" },
}

-- "Aspect of <name>"; every weapon's first aspect is Melinoë, so labels pair it with the weapon.
keys.ASPECT_NAMES = {
    BaseStaffAspect = "Melinoë",
    StaffClearCastAspect = "Circe",
    StaffSelfHitAspect = "Momus",
    StaffRaiseDeadAspect = "Anubis",
    DaggerBackstabAspect = "Melinoë",
    DaggerBlockAspect = "Artemis",
    DaggerHomingThrowAspect = "Pan",
    DaggerTripleAspect = "Morrigan",
    TorchSpecialDurationAspect = "Melinoë",
    TorchDetonateAspect = "Moros",
    TorchSprintRecallAspect = "Eos",
    TorchAutofireAspect = "Supay",
    AxeRecoveryAspect = "Melinoë",
    AxeArmCastAspect = "Charon",
    AxePerfectCriticalAspect = "Thanatos",
    AxeRallyAspect = "Nergal",
    LobAmmoBoostAspect = "Melinoë",
    LobCloseAttackAspect = "Medea",
    LobImpulseAspect = "Persephone",
    LobGunAspect = "Hel",
    BaseSuitAspect = "Melinoë",
    SuitHexAspect = "Selene",
    SuitMarkCritAspect = "Nyx",
    SuitComboAspect = "Shiva",
}

local ASPECT_WEAPONS = {}
for weapon, aspects in pairs(keys.ASPECTS) do
    for _, aspect in ipairs(aspects) do
        ASPECT_WEAPONS[aspect] = weapon
    end
end

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

--- The run's primary weapon id, from the hero's equipped weapons.
function keys.weaponOf(run)
    local weapons = run and run.Hero and run.Hero.Weapons
    if weapons == nil then
        return nil
    end
    for _, weapon in ipairs(keys.WEAPONS) do
        if weapons[weapon] then
            return weapon
        end
    end
    return nil
end

--- The run's aspect id: the weapon's aspect trait the hero carries.
function keys.aspectOf(run, weapon)
    local traits = run and run.Hero and run.Hero.TraitDictionary
    if traits == nil or weapon == nil then
        return nil
    end
    for _, aspect in ipairs(keys.ASPECTS[weapon] or {}) do
        if traits[aspect] ~= nil then
            return aspect
        end
    end
    return nil
end

function keys.resolve(run)
    local weapon = keys.weaponOf(run)
    return {
        route = keys.routeOf(run),
        weapon = weapon,
        aspect = keys.aspectOf(run, weapon),
    }
end

--- Display name for a key value, or nil when the value is unknown.
function keys.nameOf(keyName, value)
    if value == nil then
        return nil
    end
    if keyName == "route" then
        return keys.ROUTE_NAMES[value]
    end
    if keyName == "weapon" then
        return keys.WEAPON_NAMES[value]
    end
    if keyName == "aspect" then
        local weapon = ASPECT_WEAPONS[value]
        local aspectName = keys.ASPECT_NAMES[value]
        if weapon == nil or aspectName == nil then
            return nil
        end
        return keys.WEAPON_NAMES[weapon] .. " " .. aspectName
    end
    return nil
end

return keys
