local spider = require("scripts/spider")
local constants = require("scripts/constants")

describe("idle recall after finishing work", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local ghost_pos
    local original_global_enabled

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 4000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = storage.global_enabled
        storage.global_enabled = false

        storage.anchors = storage.anchors or {}
        storage.spider_to_anchor = storage.spider_to_anchor or {}
        storage.entity_to_spider = storage.entity_to_spider or {}
        storage.assigned_tasks = {}

        anchor_entity = track(surface.create_entity({
            name = "wooden-chest",
            position = base_pos,
            force = force,
        }))

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "spiderling", count = 1 })
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        anchor_id = "test_anchor_idle_" .. game.tick .. "_" .. math.random(1, 1000000)
        anchor_data = {
            type = "test",
            entity = anchor_entity,
            player_index = nil,
            surface_index = surface.index,
            position = { x = anchor_entity.position.x, y = anchor_entity.position.y },
            spiders = {},
        }
        storage.anchors[anchor_id] = anchor_data

        -- A single nearby build ghost to trigger deploy + assignment.
        ghost_pos = { x = base_pos.x + 2, y = base_pos.y }
        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = ghost_pos,
            force = force,
            expires = false,
        }))
    end)

    after_each(function()
        if anchor_id and storage.anchors then
            storage.anchors[anchor_id] = nil
        end
        storage.global_enabled = original_global_enabled

        for _, e in ipairs(created) do
            if e and e.valid then e.destroy() end
        end
    end)

    test("recalls spider about 2s after no work", function()
        local inventory = anchor_entity.get_inventory(defines.inventory.chest)

        -- First loop deploys a spider.
        remote.call("brood-engineering-test", "run_main_loop")

        after_ticks(1, function()
            -- Second loop assigns the nearby ghost.
            remote.call("brood-engineering-test", "run_main_loop")

            local spider_id = next(anchor_data.spiders)
            assert.is_not_nil(spider_id)
            local spider_data = anchor_data.spiders[spider_id]
            local spider_entity = spider_data.entity
            assert.is_true(spider_entity and spider_entity.valid)

            -- Ensure the spider is near the anchor so recall conditions apply.
            spider_entity.teleport(anchor_entity.position)

            -- Simulate task completion (skip travel/build mechanics).
            local target = spider_data.task and (spider_data.task.entity or spider_data.task.tile) or nil
            if target and target.valid then
                target.destroy()
            end
            spider.clear_task(spider_id)

            assert.are_equal("deployed_idle", spider_data.status)
            assert.is_not_nil(spider_entity.follow_target)
            assert.are_equal(anchor_entity.unit_number, spider_entity.follow_target.unit_number)

            -- Track the revived entity for cleanup, if any.
            local built = surface.find_entities_filtered({
                area = { { ghost_pos.x - 0.5, ghost_pos.y - 0.5 }, { ghost_pos.x + 0.5, ghost_pos.y + 0.5 } },
                name = "stone-furnace",
                force = force,
            })
            for _, e in ipairs(built) do track(e) end

            -- Now there is no work; start no-work timer.
            remote.call("brood-engineering-test", "run_main_loop")

            after_ticks(constants.no_work_recall_timeout_ticks + constants.main_loop_interval + 1, function()
                remote.call("brood-engineering-test", "run_main_loop")

                assert.is_nil(anchor_data.spiders[spider_id])
                assert.is_nil(storage.spider_to_anchor[spider_id])
                assert.are_equal(1, inventory.get_item_count("spiderling"))
            end)
        end)
    end)
end)
