-- settings.lua
-- Mod settings for Brood Engineering

data:extend({
    {
        type = "bool-setting",
        name = "brood-show-item-projectiles",
        setting_type = "runtime-global",
        default_value = true,
        order = "a",
    },
    {
        type = "bool-setting",
        name = "brood-debug-logging",
        setting_type = "runtime-global",
        default_value = false,
        order = "z",
    },
})
