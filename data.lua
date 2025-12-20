-- data.lua
-- Prototype definitions for Brood Engineering

-- Constants for spider configuration
local spider_scale = 0.125
local spider_leg_scale = 0.82
local spider_leg_movement_speed = 0.75
local spider_speed_modifier = 0.5

---------------------------------------------------------------------------
-- SPIDERLING ENTITY
---------------------------------------------------------------------------

-- Use the built-in spidertron creation function
local spiderling_args = {
    scale = spider_scale,
    leg_scale = spider_leg_scale,
    name = "spiderling",
    leg_thickness = 1.44,
    leg_movement_speed = spider_leg_movement_speed,
}

---@diagnostic disable-next-line: undefined-global
create_spidertron(spiderling_args)

-- Get the created prototype and modify it
local spiderling = data.raw["spider-vehicle"]["spiderling"]

spiderling.minable = { mining_time = 0.25, result = "spiderling" }
spiderling.placeable_by = { item = "spiderling", count = 1 }
spiderling.guns = nil
spiderling.inventory_size = 0
spiderling.trash_inventory_size = 0
spiderling.equipment_grid = nil
spiderling.allow_passengers = false
spiderling.is_military_target = false
spiderling.chunk_exploration_radius = 0
spiderling.torso_rotation_speed = (spiderling.torso_rotation_speed or 0.01) * 2
spiderling.torso_bob_speed = 0.8
-- Scale draw height with the visual size so tiny spiders don't render above tall foliage.
spiderling.height = (spiderling.height or 1) * spider_scale
-- Let spiderlings pass through each other to reduce navigation deadlocks.
do
    local mask = spiderling.collision_mask or {}
    if mask.layers then
        mask.not_colliding_with_itself = true
        spiderling.collision_mask = mask
    else
        local layers = {}
        for key, value in pairs(mask) do
            if type(key) == "string" and value == true then
                layers[key] = true
            elseif type(value) == "string" then
                layers[value] = true
            end
        end
        spiderling.collision_mask = {
            layers = layers,
            not_colliding_with_itself = true,
        }
    end
end
-- Force a lower render layer so tiny spiders don't draw over large objects (trees/rocks).
if spiderling.graphics_set then
    if spiderling.graphics_set.base_render_layer ~= nil then
        spiderling.graphics_set.base_render_layer = "lower-object"
    end
    if spiderling.graphics_set.render_layer ~= nil then
        spiderling.graphics_set.render_layer = "lower-object"
    end
end

-- Reduce minimap representation
if spiderling.minimap_representation then
    spiderling.minimap_representation.scale = 0.1
end

-- Add not-blueprintable flag
spiderling.flags = spiderling.flags or {}
table.insert(spiderling.flags, "not-blueprintable")

-- Reduce light intensity
if spiderling.graphics_set and spiderling.graphics_set.light then
    for _, light in pairs(spiderling.graphics_set.light) do
        light.intensity = (light.intensity or 1) / 3
    end
end

-- Reduce sounds
if spiderling.working_sound then
    spiderling.working_sound.probability = 0.1
end

---------------------------------------------------------------------------
-- SPIDER LEG MODIFICATIONS
---------------------------------------------------------------------------

-- Custom collision layer for spider legs
data:extend({
    {
        type = "collision-layer",
        name = "brood_spider_leg",
    },
})

-- Modify spider legs
local function modify_spider_legs(leg_spec)
    if leg_spec.leg_hit_the_ground_trigger then
        for _, trigger in pairs(leg_spec.leg_hit_the_ground_trigger) do
            trigger.repeat_count = 1
            trigger.probability = 0.03
        end
    end

    local leg_name = leg_spec.leg
    local leg_proto = data.raw["spider-leg"][leg_name]

    if leg_proto then
        leg_proto.localised_name = { "entity-name.spiderling-leg" }
        leg_proto.walking_sound_volume_modifier = 0

        if leg_proto.working_sound then
            leg_proto.working_sound.probability = 0.1
        end

        if leg_proto.graphics_set then
            leg_proto.graphics_set.joint_render_layer = "lower-object"
            if leg_proto.graphics_set.upper_part then
                leg_proto.graphics_set.upper_part.render_layer = "lower-object"
            end
            if leg_proto.graphics_set.lower_part then
                leg_proto.graphics_set.lower_part.render_layer = "lower-object"
            end
            if leg_proto.graphics_set.foot then
                leg_proto.graphics_set.foot.render_layer = "lower-object"
            end
        end

        -- Set collision mask
        leg_proto.collision_mask = {
            layers = {
                water_tile = true,
                object = true,
                empty_space = true,
                lava_tile = true,
                rail_support = true,
                cliff = true,
                brood_spider_leg = true,
            },
            not_colliding_with_itself = true,
            consider_tile_transitions = false,
            colliding_with_tiles_only = false,
        }

        -- Increase step size
        if leg_proto.minimal_step_size then
            leg_proto.minimal_step_size = leg_proto.minimal_step_size * 4
        end
    end
end

-- Apply leg modifications
if spiderling.spider_engine and spiderling.spider_engine.legs then
    local legs = spiderling.spider_engine.legs
    if legs[1] then
        for _, leg in pairs(legs) do
            modify_spider_legs(leg)
        end
    else
        modify_spider_legs(legs)
    end
end

do
    local box = spiderling.selection_box
    if box and box[1] and box[2] and box[1][1] and box[1][2] and box[2][1] and box[2][2] then
        box[1][1] = box[1][1] * 2
        box[1][2] = box[1][2] * 2
        box[2][1] = box[2][1] * 2
        box[2][2] = box[2][2] * 2
    end
end

data:extend({ spiderling })

---------------------------------------------------------------------------
-- SPIDERLING ITEM (Capsule for throwing)
---------------------------------------------------------------------------

local spidertron_item = data.raw["item-with-entity-data"]["spidertron"]

data:extend({
    {
        type = "capsule",
        name = "spiderling",
        icon = spidertron_item.icon,
        icon_size = spidertron_item.icon_size,
        stack_size = 50,
        subgroup = "logistic-network",
        order = "a[robot]-b[spiderling]",
        capsule_action = {
            type = "throw",
            attack_parameters = {
                activation_type = "throw",
                ammo_category = "capsule",
                type = "projectile",
                cooldown = 10,
                projectile_creation_distance = 0.3,
                range = 50,
                ammo_type = {
                    category = "capsule",
                    target_type = "position",
                },
            },
        },
    },
})

---------------------------------------------------------------------------
-- SPIDERLING RECIPE
---------------------------------------------------------------------------

data:extend({
    {
        type = "recipe",
        name = "spiderling",
        enabled = false,
        energy_required = 8,
        ingredients = {
            { type = "item", name = "electronic-circuit", amount = 4 },
            { type = "item", name = "iron-plate", amount = 12 },
            { type = "item", name = "inserter", amount = 8 },
            { type = "item", name = "raw-fish", amount = 1 },
        },
        results = {
            { type = "item", name = "spiderling", amount = 1 },
        },
        subgroup = "logistic-network",
        order = "a[robot]-b[spiderling]",
    },
})

---------------------------------------------------------------------------
-- TECHNOLOGY
---------------------------------------------------------------------------

data:extend({
    {
        type = "technology",
        name = "brood-engineering",
        icon = "__base__/graphics/technology/spidertron.png",
        icon_size = 256,
        effects = {
            {
                type = "unlock-recipe",
                recipe = "spiderling",
            },
        },
        prerequisites = { "electronics" },
        research_trigger = {
            type = "mine-entity",
            entity = "fish",
        },
    },
})

---------------------------------------------------------------------------
-- SHORTCUT (Toggle button)
---------------------------------------------------------------------------

data:extend({
    {
        type = "shortcut",
        name = "brood-toggle",
        action = "lua",
        associated_control_input = "brood-toggle",
        icon = "__base__/graphics/icons/spidertron.png",
        icon_size = 64,
        small_icon = "__base__/graphics/icons/spidertron.png",
        small_icon_size = 64,
        toggleable = true,
    },
})

---------------------------------------------------------------------------
-- CUSTOM INPUT (Hotkey)
---------------------------------------------------------------------------

data:extend({
    {
        type = "custom-input",
        name = "brood-toggle",
        key_sequence = "ALT + B",
        action = "lua",
    },
})

---------------------------------------------------------------------------
-- PROJECTILE (for spider deployment animation)
---------------------------------------------------------------------------

local distractor_capsule = data.raw["projectile"]["distractor-capsule"]

data:extend({
    {
        type = "projectile",
        name = "spiderling-projectile",
        acceleration = 0.005,
        action = {
            type = "direct",
            action_delivery = {
                type = "instant",
                target_effects = {
                    {
                        type = "create-entity",
                        entity_name = "spiderling",
                        show_in_tooltip = true,
                        trigger_created_entity = true,
                    },
                },
            },
        },
        animation = distractor_capsule and distractor_capsule.animation or nil,
        shadow = distractor_capsule and distractor_capsule.shadow or nil,
        flags = { "not-on-map" },
        enable_drawing_with_mask = true,
        hidden = true,
    },
})
