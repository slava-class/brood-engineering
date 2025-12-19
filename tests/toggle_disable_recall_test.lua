local spider = require("scripts/spider")
local utils = require("scripts/utils")
local anchor = require("scripts/anchor")
local fapi = require("scripts/fapi")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("toggle disable recall", function()
    return test_utils.anchor_opts.chest({
        x_base = 12000,
        radii = "small",
        spiderlings = 1,
        anchor_seed = {},
    })
end, function(ctx)
    test("disabling via brood-toggle recalls and returns spiderling", function()
        local inv = ctx.anchor_inventory
        assert(inv and inv.valid)
        inv.clear()
        inv.insert({ name = "spiderling", count = 1, quality = "normal" })
        assert.are_equal(1, inv.get_item_count("spiderling"))

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inv.get_item_count("spiderling"))

        storage.global_enabled = true
        test_utils.press_brood_toggle(1)

        assert.are_equal(1, inv.get_item_count("spiderling"))
        assert.is_nil(test_utils.find_spider_data(ctx, spider_id))
        assert.is_nil(storage.spider_to_anchor[spider_id])
    end)

    test("disabling via brood-toggle returns carried spider inventories into anchor", function()
        local inv = ctx.anchor_inventory
        assert(inv and inv.valid)
        inv.clear()

        local e = ctx.spawn({
            name = "spidertron",
            offset = { x = 6, y = 0 },
        })
        assert(e and e.valid)

        local spider_id = "test_spidertron_" .. game.tick .. "_" .. math.random(1, 1000000)
        local entity_id = utils.get_entity_id(e)
        ctx.anchor_data.spiders[spider_id] = {
            entity = e,
            entity_id = entity_id,
            anchor_id = ctx.anchor_id,
            status = "deployed_idle",
            task = nil,
            idle_since = nil,
        }
        storage.spider_to_anchor[spider_id] = ctx.anchor_id
        storage.entity_to_spider[entity_id] = spider_id
        ctx.defer(function()
            if storage.assigned_tasks then
                for task_id, sid in pairs(storage.assigned_tasks) do
                    if sid == spider_id then
                        storage.assigned_tasks[task_id] = nil
                    end
                end
            end
            if storage.entity_to_spider then
                storage.entity_to_spider[entity_id] = nil
            end
            if storage.spider_to_anchor then
                storage.spider_to_anchor[spider_id] = nil
            end
            if ctx.anchor_data and ctx.anchor_data.spiders then
                ctx.anchor_data.spiders[spider_id] = nil
            end
            if e and e.valid then
                fapi.destroy_quiet(e)
            end
        end)

        local trunk = e.get_inventory(defines.inventory.spider_trunk)
        assert(trunk and trunk.valid)
        trunk.clear()
        assert.are_equal(7, trunk.insert({ name = "iron-plate", count = 7, quality = "normal" }))
        assert.are_equal(3, trunk.insert({ name = "copper-plate", count = 3, quality = "normal" }))

        storage.global_enabled = true
        test_utils.press_brood_toggle(1)

        assert.are_equal(1, inv.get_item_count({ name = "spidertron", quality = "normal" }))
        assert.is_true(inv.get_item_count({ name = "iron-plate", quality = "normal" }) >= 7)
        assert.is_true(inv.get_item_count({ name = "copper-plate", quality = "normal" }) >= 3)
        assert.is_nil(test_utils.find_spider_data(ctx, spider_id))
        assert.is_nil(storage.spider_to_anchor[spider_id])
    end)

    test("re-enabling does not auto-deploy when there is no executable work", function()
        local inv = ctx.anchor_inventory
        assert(inv and inv.valid)
        inv.clear()
        inv.insert({ name = "spiderling", count = 3, quality = "normal" })

        ctx.clear_area(ctx.base_pos, 25)
        ctx.assert_no_ghosts({
            { ctx.base_pos.x - 10, ctx.base_pos.y - 10 },
            { ctx.base_pos.x + 10, ctx.base_pos.y + 10 },
        })

        storage.global_enabled = false
        test_utils.press_brood_toggle(1)
        assert.is_true(storage.global_enabled)

        for _ = 1, 3 do
            test_utils.run_main_loop()
        end

        assert.are_equal(0, anchor.get_spider_count(ctx.anchor_data))
        assert.are_equal(3, inv.get_item_count("spiderling"))
    end)
end)
