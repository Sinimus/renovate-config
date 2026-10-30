#!/usr/bin/env bash
# Validate the presets with Renovate's own validator and assert the invariants
# the shared config promises. Run from the repo root: scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Renovate's validator, run on a copy named renovate.json so it is checked as repo config.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for preset in default lockfile; do
  mkdir "$tmp/$preset"
  cp "$preset.json" "$tmp/$preset/renovate.json"
  (cd "$tmp/$preset" && fnm exec --using 24.22.2 pnpm dlx --package=renovate renovate-config-validator --strict renovate.json 2>&1 \
    | grep -q "Config validated successfully") || fail "$preset.json does not validate"
done

# 2. Invariants of default.json.
d=default.json
[ "$(jq -r '.minimumReleaseAge' $d)" = "7 days" ] || fail "minimumReleaseAge is not 7 days"
[ "$(jq -r '.vulnerabilityAlerts.minimumReleaseAge' $d)" = "7 days" ] || fail "vulnerabilityAlerts lost the 7-day age"
[ "$(jq -r '.internalChecksFilter' $d)" = "strict" ] || fail "internalChecksFilter is not strict"
[ "$(jq -r '.automerge' $d)" = "false" ] || fail "top-level automerge must be false"
jq -e '.extends | index("helpers:pinGitHubActionDigests")' $d >/dev/null || fail "Actions are not pinned"

# Exactly one rule may enable automerge, it must be limited to the static sites and to non-major updates.
[ "$(jq '[.packageRules[] | select(.automerge == true)] | length' $d)" = "1" ] || fail "expected exactly one automerge rule"
jq -e '.packageRules[] | select(.automerge == true) | (.matchRepositories | length) > 0 and (.matchUpdateTypes | index("major") | not)' $d >/dev/null \
  || fail "automerge rule is not limited to listed repos and non-major updates"
expected='["Sinimus/eldritch-horror-companion-app","Sinimus/gwt-new_zealand-companion","Sinimus/hegemony-companion-app","Sinimus/jotl-companion","Sinimus/root-companion","Sinimus/stationfall-companion-app"]'
[ "$(jq -c '[.packageRules[] | select(.automerge == true) | .matchRepositories[]] | sort' $d)" = "$expected" ] \
  || fail "automerge repository list differs from the agreed sites (r508)"

# lockfile.json never automerges.
[ "$(jq -r '.lockFileMaintenance.automerge' lockfile.json)" = "false" ] || fail "lockfile preset must not automerge"

echo "OK"
