local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
---@module "adamant-ModpackLib"
---@type AdamantModpackLib
local lib = mods['adamant-ModpackLib']
local reload = mods['SGG_Modding-ReLoad']

local PACK_ID = "speedrun"
local MODULE_ID = "LiveSplit"
local PLUGIN_GUID = _PLUGIN.guid

local loader = reload.auto_single()

local function init()
    import_as_fallback(rom.game)
    local data = import("data.lua")
    local actions = import("actions.lua")

    local module = lib.createModule({
        pluginGuid = PLUGIN_GUID,
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "LiveSplit",
        tooltip = "LiveSplit-style timer and recording tools for speedruns.",
        hash = false,
    })
    if not module then
        return
    end

    module.data.define(data.buildStorage())
    module.status.define(data.buildStatus())
    local timer = import("timer/00_init.lua")
    local controller = import("controller.lua", nil, {
        timer = timer,
    })
    local display = import("display/display.lua", nil, {
        timer = timer,
        overlayEvents = controller.overlayEvents,
        fonts = module.overlays.fonts,
    })
    local sharedSnapshot = import("shared_snapshot.lua", nil, {
        timer = timer,
    })
    local ui = import("ui.lua")

    actions.attach(module, controller)
    sharedSnapshot.register(module.shared)
    sharedSnapshot.attach(timer)
    timer.installHooks(module.hooks)
    display.registerOverlays(module.overlays)
    ui.attach(module, {
        getRecordingStatus = timer.recording.status,
    })
    module.onCommit(controller.onCommit)
    module.onActivate(controller.onActivate)

    module.fallbackUi.attachGuiOnce(function(fallbackUi)
        rom.gui.add_imgui(fallbackUi.renderWindow)
        rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
    end)

    local ok = module.activate()
    if not ok then
        return
    end
end

modutil.once_loaded.game(function()
    loader.load(nil, init)
end)
