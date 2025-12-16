#!/usr/bin/env bash
set -euo pipefail

# Capture a Factorio blueprint string from the macOS clipboard (or stdin) into a Lua module
# so FactorioTest can import/build it during tests.
#
# Usage:
#   bin/capture-blueprint-fixture.sh "<name>"            # reads pbpaste
#   pbpaste | bin/capture-blueprint-fixture.sh "<name>"  # reads stdin
#
# Output:
#   tests/fixtures/blueprints/<name>.lua
#   tests/fixtures/blueprints.lua (manifest)

name="${1:-}"
if [ -z "${name}" ]; then
  echo "Usage: $0 \"<name>\"" >&2
  exit 2
fi

safe_name="$(printf "%s" "${name}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/_/g' | sed -E 's/^_+|_+$//g')"
if [ -z "${safe_name}" ]; then
  echo "Invalid name: ${name}" >&2
  exit 2
fi

out="tests/fixtures/blueprints/${safe_name}.lua"
manifest="tests/fixtures/blueprints.lua"

bp=""
if [ -t 0 ]; then
  if command -v pbpaste >/dev/null 2>&1; then
    bp="$(pbpaste || true)"
  fi
else
  bp="$(cat)"
fi

bp="$(printf "%s" "${bp}" | tr -d '\r\n')"

mkdir -p "$(dirname "${out}")"

if [ -z "${bp}" ]; then
  cat >"${out}" <<'EOF'
-- Auto-generated fixture (empty).
-- Run `bin/capture-blueprint-fixture.sh "<name>"` to capture a blueprint export string.
return ""
EOF
  echo "Wrote empty fixture to ${out} (no clipboard/stdin content found)." >&2
  exit 0
fi

cat >"${out}" <<EOF
-- Auto-generated fixture.
-- Do not edit by hand; re-run \`bin/capture-blueprint-fixture.sh "<name>"\`.
return [[${bp}]]
EOF

mkdir -p "$(dirname "${manifest}")"
if [ ! -f "${manifest}" ]; then
  cat >"${manifest}" <<'EOF'
-- Blueprint fixture manifest.
--
-- Add new fixtures with:
--   bin/capture-blueprint-fixture.sh "<name>"
--
-- Each entry is a module path that returns a blueprint export string.
return {
    { name = "clipboard", module = "tests/fixtures/blueprints/clipboard" },
}
EOF
fi

module="tests/fixtures/blueprints/${safe_name}"
if ! grep -Fq "module = \"${module}\"" "${manifest}" 2>/dev/null; then
  tmp="$(mktemp)"
  lua_name="$(printf "%s" "${name}" | sed -E 's/\\/\\\\/g; s/"/\\"/g')"
  awk -v entry="    { name = \"${lua_name}\", module = \"${module}\" }," '
    BEGIN { added = 0 }
    {
      # POSIX awk does not support \s; use a character class for whitespace.
      if (!added && $0 ~ /^}[[:space:]]*$/) { print entry; added = 1 }
      print
    }
  ' "${manifest}" >"${tmp}"
  mv "${tmp}" "${manifest}"
fi

echo "Wrote blueprint fixture to ${out} (${#bp} chars) and updated ${manifest}." >&2
