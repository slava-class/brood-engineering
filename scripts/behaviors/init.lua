-- scripts/behaviors/init.lua
-- Exports all behaviors in priority order

local behaviors = {
    require("scripts/behaviors/unblock_deconstruct"),
    require("scripts/behaviors/build_foundation"),
    require("scripts/behaviors/build_entity"),
    require("scripts/behaviors/upgrade"),
    require("scripts/behaviors/item_proxy"),
    require("scripts/behaviors/deconstruct_entity"),
    require("scripts/behaviors/build_tile"),
    require("scripts/behaviors/deconstruct_tile"),
}

-- Sort by priority (should already be in order, but just in case)
table.sort(behaviors, function(a, b) return a.priority < b.priority end)

return behaviors
