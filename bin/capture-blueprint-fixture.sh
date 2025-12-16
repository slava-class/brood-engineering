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

python3 - <<'PY' <<<"${bp}" || true
import sys, base64, zlib, json

bp = sys.stdin.read().strip()
if not bp:
    raise SystemExit(0)
if not bp.startswith("0"):
    print(f"Captured string does not look like a Factorio export (missing leading '0'); len={len(bp)}", file=sys.stderr)
    raise SystemExit(0)

try:
    raw = base64.b64decode(bp[1:])
    payload = zlib.decompress(raw)
    obj = json.loads(payload)
except Exception as e:
    print(f"Captured export decode failed: {e}", file=sys.stderr)
    raise SystemExit(0)

def decode_version(v):
    if not isinstance(v, int):
        return None
    major = (v >> 48) & 0xFFFF
    minor = (v >> 32) & 0xFFFF
    patch = (v >> 16) & 0xFFFF
    dev = v & 0xFFFF
    return major, minor, patch, dev

kind = next((k for k in ("blueprint", "blueprint_book", "deconstruction_planner", "upgrade_planner") if k in obj), None)
if not kind:
    print(f"Captured export type: unknown (top-level keys: {list(obj.keys())})", file=sys.stderr)
    raise SystemExit(0)

root = obj.get(kind, {}) if isinstance(obj, dict) else {}
label = root.get("label")
version = root.get("version")
decoded = decode_version(version)
version_str = f"{decoded[0]}.{decoded[1]}.{decoded[2]}.{decoded[3]}" if decoded else str(version)

extra = ""
if kind == "blueprint_book":
    extra = f" blueprints={len(root.get('blueprints') or [])}"
elif kind == "blueprint":
    extra = f" entities={len(root.get('entities') or [])} tiles={len(root.get('tiles') or [])}"

print(
    f"Captured export type={kind} label={label!r} version={version_str} ({version}){extra}",
    file=sys.stderr,
)
PY

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
-- Each entry loads a blueprint export string at module parse time.
return {
    { name = "clipboard", data = require("tests/fixtures/blueprints/clipboard") },
}
EOF
fi

module="tests/fixtures/blueprints/${safe_name}"
if ! grep -Fq "require(\"${module}\")" "${manifest}" 2>/dev/null; then
  tmp="$(mktemp)"
  lua_name="$(printf "%s" "${name}" | sed -E 's/\\/\\\\/g; s/"/\\"/g')"
  awk -v entry="    { name = \"${lua_name}\", data = require(\"${module}\") }," '
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
