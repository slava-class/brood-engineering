-- Blueprint fixture manifest.
--
-- Add new fixtures with:
--   bin/capture-blueprint-fixture.sh "<name>"
--
-- Each entry loads a blueprint export string at module parse time.
return {
    -- NOTE: FactorioTest disallows `require()` during test runtime ("outside of control.lua parsing"),
    -- so we load fixture strings here at module parse time.
    { name = "clipboard", data = require("tests/fixtures/blueprints/clipboard") },
    { name = "brood_test_book", data = require("tests/fixtures/blueprints/brood_test_book") },
    { name = "brood_test_tile_blueprint", data = require("tests/fixtures/blueprints/brood_test_tile_blueprint") },
    { name = "full_base_default", data = require("tests/fixtures/blueprints/full_base_default") },
    { name = "sciences_nauvis", data = require("tests/fixtures/blueprints/sciences_nauvis") },
    { name = "debut_de_partie", data = require("tests/fixtures/blueprints/debut_de_partie") },
}
