local constants = require("scripts/constants")
local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("upgrade behavior", function()
    return test_utils.anchor_opts.chest({
        x_base = 11100,
        radii = "small",
        spiderlings = 1,
    })
end, function(ctx)
    local function clear_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, { anchor_entity = ctx.anchor_entity, skip_spiders = true })
    end

    test("upgrades an entity and swaps items in anchor inventory", function()
        local target_pos = ctx.pos({ x = 10, y = 0 })
        clear_area(target_pos, 10)

        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        inventory.clear()
        inventory.insert({ name = "spiderling", count = 1 })
        inventory.insert({ name = "fast-transport-belt", count = 1, quality = "normal" })

        local belt = ctx.spawn({
            name = "transport-belt",
            position = target_pos,
            direction = defines.direction.east,
        })
        assert.is_true(belt and belt.valid)

        local ordered = belt.order_upgrade({
            force = ctx.force,
            target = { name = "fast-transport-belt", quality = "normal" },
        })
        assert.is_true(ordered)
        assert.is_true(belt.to_be_upgraded())

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        test_utils.wait_until({
            timeout_ticks = 60 * 30,
            description = "upgrade completes",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local area = {
                    { target_pos.x - 0.5, target_pos.y - 0.5 },
                    { target_pos.x + 0.5, target_pos.y + 0.5 },
                }
                local upgraded = ctx.surface.find_entities_filtered({
                    area = area,
                    name = "fast-transport-belt",
                    force = ctx.force,
                })
                if upgraded and #upgraded > 0 then
                    assert.are_equal(0, inventory.get_item_count({ name = "fast-transport-belt", quality = "normal" }))
                    assert.is_true(inventory.get_item_count({ name = "transport-belt", quality = "normal" }) >= 1)
                    return true
                end
                return false
            end,
        })
    end)
end)
