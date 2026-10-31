#!/usr/bin/env bash
# Negative tests of scripts/check.sh: each case breaks one invariant in a copy of the presets
# and expects check.sh to fail; the unmodified copy must pass. Run: scripts/test-check.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_check() { CONFIG_DIR="$1" SKIP_VALIDATOR=1 bash "$root/scripts/check.sh" 2>"$tmp/stderr" >/dev/null; }

# copy <name>: a fresh copy of the presets in $tmp/<name>
copy() { mkdir "$tmp/$1"; cp "$root"/*.json "$tmp/$1/"; }

# mutate <name> <file> <jq filter>: the case expects check.sh to fail
fails=0
mutate() {
  local name="$1" file="$2" filter="$3"
  copy "$name"
  jq "$filter" "$tmp/$name/$file" > "$tmp/$name/$file.new" && mv "$tmp/$name/$file.new" "$tmp/$name/$file"
  if run_check "$tmp/$name"; then
    echo "NOT CAUGHT: $name"; fails=$((fails + 1))
  else
    echo "caught: $name ($(cat "$tmp/stderr"))"
  fi
}

copy unmodified
run_check "$tmp/unmodified" || { echo "FAIL: unmodified presets do not pass"; exit 1; }
echo "passes: unmodified"

C='(.packageRules[] | select(.automerge == true and .matchManagers == ["!github-actions"]))'
BT='(.packageRules[] | select(.groupSlug == "weekly-tooling"))'
BA='(.packageRules[] | select(.automerge == true and .matchManagers == ["github-actions"]))'

mutate c-extra-repo          default.json "$C.matchRepositories += [\"Sinimus/homegym\"]"
mutate c-major               default.json "$C.matchUpdateTypes += [\"major\"]"
mutate c-includes-actions    default.json "del($C.matchManagers)"
mutate c-lockfile            default.json "$C.matchUpdateTypes += [\"lockFileMaintenance\"]"
mutate c-platform-automerge  default.json "$C.platformAutomerge = true"
mutate c-narrowed-by-name    default.json "$C.matchPackageNames = [\"react\"]"
mutate b-extra-tool          default.json "$BT.matchPackageNames += [\"typescript\"]"
mutate b-runtime-deptype     default.json "$BT.matchDepTypes += [\"dependencies\"]"
mutate b-extra-repo          default.json "$BA.matchRepositories += [\"Sinimus/up-kompas\"]"
mutate b-actions-major       default.json "$BA.matchUpdateTypes += [\"major\"]"
mutate b-actions-all-deptypes  default.json "del($BA.matchDepTypes)"
mutate b-versions-automerge  default.json '(.packageRules[] | select(.groupSlug == "github-actions-versions")).automerge = true'
mutate b-versions-missing    default.json '.packageRules |= map(select(.groupSlug != "github-actions-versions"))'
mutate deploy-rule-first     default.json '(.packageRules | map(select(.groupSlug == "github-actions-deploy"))) as $d | .packageRules = ($d + (.packageRules | map(select(.groupSlug != "github-actions-deploy"))))'
mutate deploy-rule-automerge default.json '(.packageRules[] | select(.groupSlug == "github-actions-deploy")).automerge = true'
mutate new-unscoped-rule     default.json '.packageRules += [{"matchUpdateTypes": ["patch"], "automerge": true, "automergeType": "pr", "platformAutomerge": false}]'
mutate tooling-group-elsewhere default.json '.packageRules += [{"matchPackageNames": ["react"], "groupName": "weekly tooling", "groupSlug": "weekly-tooling"}]'
mutate top-level-automerge   default.json '.automerge = true'
mutate major-object          default.json '.major = {"automerge": true}'
mutate security-automerge    default.json '.vulnerabilityAlerts.automerge = true'
mutate actions-major-merged  default.json '(.packageRules[] | select(.groupSlug == "github-actions-major")).automerge = true'
mutate pin-unversioned       default.json '(.packageRules[] | select(.pinDigests == true)) |= del(.matchCurrentValue)'
mutate lockfile-automerge    lockfile.json '.lockFileMaintenance.automerge = true'
mutate binaries-automerge    github-binaries.json '.packageRules = [{"matchPackageNames": ["*"], "automerge": true}]'

[ "$fails" = 0 ] || { echo "FAIL: $fails case(s) not caught"; exit 1; }
echo "OK"
