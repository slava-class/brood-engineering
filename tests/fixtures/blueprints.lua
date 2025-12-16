-- Blueprint fixture manifest.
--
-- Add new fixtures with:
--   bin/capture-blueprint-fixture.sh "<name>"
--
-- Each entry is a module path that returns a blueprint export string.
return {
    { name = "clipboard", module = "tests/fixtures/blueprints/clipboard" },
    { name = "full_base_default", module = "tests/fixtures/blueprints/full_base_default" },
}
