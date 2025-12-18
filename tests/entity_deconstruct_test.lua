local deconstruct_entity = require("scripts/behaviors/deconstruct_entity")
local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("entity deconstruction", function()
    return {
        base_pos = test_utils.random_base_pos(9500),
        ensure_chunks_radius = 1,
        clean_radius = 60,
        clear_radius = 16,
        anchor_name = "wooden-chest",
        anchor_inventory_id = defines.inventory.chest,
        anchor_seed = {},
        anchor_id_prefix = "test_anchor_entity_decon",
    }
end, function(ctx)
    local function clear_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, { anchor_entity = ctx.anchor_entity, skip_spiders = true })
    end

    test("mines an entity and transfers its inventories to the anchor inventory", function()
        local target_offset = { x = 12, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 10)

        local furnace = ctx.spawn({
            name = "stone-furnace",
            offset = target_offset,
            direction = defines.direction.north,
        })
        assert.is_true(furnace and furnace.valid)

        local source = furnace.get_inventory(defines.inventory.crafter_input)
        local fuel = furnace.get_inventory(defines.inventory.fuel)
        assert.is_true(source and source.valid)
        assert.is_true(fuel and fuel.valid)

        source.insert({ name = "iron-ore", count = 10, quality = "normal" })
        fuel.insert({ name = "coal", count = 5, quality = "normal" })

        furnace.order_deconstruction(ctx.force)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        assert.is_true(deconstruct_entity.can_execute(furnace, inventory))
        assert.is_true(deconstruct_entity.execute({}, furnace, inventory, ctx.anchor_data))
        assert.is_true(not furnace.valid)
        assert.is_true(inventory.get_item_count({ name = "stone-furnace", quality = "normal" }) >= 1)
        assert.is_true(inventory.get_item_count({ name = "iron-ore", quality = "normal" }) >= 10)
        assert.is_true(inventory.get_item_count({ name = "coal", quality = "normal" }) >= 5)
    end)

    test("collects nearby item-entities when mining a belt", function()
        local target_offset = { x = 18, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 10)

        local belt = ctx.spawn({
            name = "transport-belt",
            offset = target_offset,
            direction = defines.direction.east,
        })
        assert.is_true(belt and belt.valid)

        local line = belt.get_transport_line(1)
        assert.is_true(line and line.valid)

        local inserted_count = 2
        ctx.surface.spill_item_stack({
            position = target_pos,
            stack = { name = "iron-plate", count = inserted_count, quality = "normal" },
            allow_belts = false,
            max_radius = 0,
        })

        belt.order_deconstruction(ctx.force)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        assert.is_true(deconstruct_entity.can_execute(belt, inventory))
        assert.is_true(deconstruct_entity.execute({}, belt, inventory, ctx.anchor_data))
        assert.is_true(not belt.valid)
        assert.is_true(inventory.get_item_count({ name = "transport-belt", quality = "normal" }) >= 1)
        assert.is_true(inventory.get_item_count({ name = "iron-plate", quality = "normal" }) >= inserted_count)
    end)

    test("collects items from belt transport lines when mining", function()
        local target_offset = { x = 24, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 10)

        local belt = ctx.spawn({
            name = "transport-belt",
            offset = target_offset,
            direction = defines.direction.east,
        })
        assert.is_true(belt and belt.valid)

        local line = belt.get_transport_line(1)
        assert.is_true(line and line.valid)

        local function sum_named_counts(obj, wanted_name)
            if type(obj) ~= "table" then
                return 0
            end
            local total = 0
            for k, v in pairs(obj) do
                if type(v) == "number" then
                    if k == wanted_name then
                        total = total + v
                    end
                elseif type(v) == "table" then
                    if v.name == wanted_name and type(v.count) == "number" then
                        total = total + v.count
                    else
                        total = total + sum_named_counts(v, wanted_name)
                    end
                end
            end
            return total
        end

        local function try_insert_one()
            local ok, result = pcall(function()
                return line.insert_at_back("iron-plate")
            end)
            if ok and result == true then
                return true
            end

            ok, result = pcall(function()
                return line.insert_at_back({ name = "iron-plate", count = 1, quality = "normal" })
            end)
            if ok and result == true then
                return true
            end

            ok, result = pcall(function()
                return line.insert_at_back(1, "iron-plate")
            end)
            if ok and result == true then
                return true
            end

            ok, result = pcall(function()
                return line.insert_at_back(1, { name = "iron-plate", count = 1, quality = "normal" })
            end)
            if ok and result == true then
                return true
            end

            return false
        end

        local desired_count = 4
        for _ = 1, desired_count do
            if not try_insert_one() then
                break
            end
        end

        local contents = line.get_contents()
        local on_belt = sum_named_counts(contents, "iron-plate")
        if on_belt < desired_count then
            ctx.surface.spill_item_stack({
                position = target_pos,
                stack = { name = "iron-plate", count = desired_count, quality = "normal" },
                allow_belts = true,
                max_radius = 0,
            })
            contents = line.get_contents()
            on_belt = sum_named_counts(contents, "iron-plate")
        end

        assert.is_true(on_belt > 0)

        belt.order_deconstruction(ctx.force)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        assert.is_true(deconstruct_entity.can_execute(belt, inventory))
        assert.is_true(deconstruct_entity.execute({}, belt, inventory, ctx.anchor_data))
        assert.is_true(not belt.valid)
        assert.is_true(inventory.get_item_count({ name = "transport-belt", quality = "normal" }) >= 1)
        assert.is_true(inventory.get_item_count({ name = "iron-plate", quality = "normal" }) >= on_belt)
    end)
end)
