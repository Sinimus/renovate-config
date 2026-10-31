#!/usr/bin/env bash
# Validate the presets with Renovate's own validator and assert the invariants
# the shared config promises. Run from anywhere: scripts/check.sh
# CONFIG_DIR points at another copy of the presets (scripts/test-check.sh uses it);
# SKIP_VALIDATOR=1 skips step 1, which needs the network and takes about a minute.
set -euo pipefail
cd "${CONFIG_DIR:-$(dirname "$0")/..}"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The automerge classes (owner's ruling r617, 31 October 2026). Changing a list here and in
# default.json is the only way to let a repository or a tool merge itself; one entry per line.
# Class B: repositories that do not deploy on merge. Tooling and non-deploying Actions automerge.
CLASS_B=(
  Sinimus/konzole
  Sinimus/unraid-scripts
  Sinimus/rag-service
  Sinimus/nanoclaw
  Sinimus/kuzu-mcp-server
)
# Class C: pull requests build the production image, open every key page in a headless browser,
# and the deploy runs only after those checks. The whole weekly group automerges, Actions excepted.
CLASS_C=(
  Sinimus/jotl-companion
  Sinimus/hegemony-companion-app
  Sinimus/gwt-new_zealand-companion
  Sinimus/root-companion
)
# The only package names the "weekly tooling" group may hold.
TOOLING=(
  eslint "@eslint/**" "eslint-*" typescript-eslint "@typescript-eslint/**"
  prettier "prettier-plugin-*" "@types/**"
  vitest "@vitest/**" jest "@jest/**" "jest-*" "@testing-library/**" "@playwright/test"
  husky lint-staged knip
  ruff mypy pytest "pytest-*" "types-*"
)
NON_MAJOR='["digest","minor","patch","pin","pinDigest"]'
DEV_DEP_TYPES='["dependency-groups","devDependencies","tool.uv.dev-dependencies"]'

json_array() { printf '%s\n' "$@" | jq -R . | jq -sc 'sort'; }
B="$(json_array "${CLASS_B[@]}")"
C="$(json_array "${CLASS_C[@]}")"
T="$(json_array "${TOOLING[@]}")"

# 1. Renovate's validator, run on a copy named renovate.json so it is checked as repo config.
if [ "${SKIP_VALIDATOR:-0}" != 1 ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  for preset in default lockfile github-binaries; do
    mkdir "$tmp/$preset"
    cp "$preset.json" "$tmp/$preset/renovate.json"
    (cd "$tmp/$preset" && fnm exec --using 24.22.2 pnpm dlx --package=renovate renovate-config-validator --strict renovate.json 2>&1 \
      | grep -q "Config validated successfully") || fail "$preset.json does not validate"
  done
fi

# 2. Invariants of default.json.
d=default.json
[ "$(jq -r '.minimumReleaseAge' $d)" = "7 days" ] || fail "minimumReleaseAge is not 7 days"
# Security PRs: 2-day fast path (r616), never automerged. Renovate applies vulnerabilityAlerts
# as the last package rule of each alert, so this wins over classes B and C.
[ "$(jq -r '.vulnerabilityAlerts.minimumReleaseAge' $d)" = "2 days" ] || fail "vulnerabilityAlerts age is not 2 days"
[ "$(jq -r '.vulnerabilityAlerts.automerge' $d)" = "false" ] || fail "vulnerabilityAlerts must set automerge false"
[ "$(jq -r '.internalChecksFilter' $d)" = "strict" ] || fail "internalChecksFilter is not strict"
[ "$(jq -r '.automerge' $d)" = "false" ] || fail "top-level automerge must be false"
jq -e '.extends | index("helpers:pinGitHubActionDigests")' $d >/dev/null || fail "Actions are not pinned"

# OSV alerts on; the GHCR age waiver covers only the owner's images and only digests.
[ "$(jq -r '.osvVulnerabilityAlerts' $d)" = "true" ] || fail "osvVulnerabilityAlerts is not on"
[ "$(jq -c '[.packageRules[] | select(.matchDatasources == ["docker"] and has("minimumReleaseAge") and .minimumReleaseAge == null) | {p: .matchPackageNames, u: .matchUpdateTypes}]' $d)" = '[{"p":["ghcr.io/sinimus/**"],"u":["digest"]}]' ] \
  || fail "the docker age waiver must be exactly ghcr.io/sinimus/** digests"
jq -e '.packageRules[] | select(.groupSlug == "github-actions") | .matchManagers == ["github-actions"] and (.matchUpdateTypes | index("major") | not)' $d >/dev/null \
  || fail "GitHub Actions group missing or includes major updates"
jq -e '[.packageRules[] | select(.groupSlug == "github-actions-major")] | length == 1 and (.[0].matchManagers == ["github-actions"]) and (.[0].matchUpdateTypes == ["major"]) and (.[0].automerge != true)' $d >/dev/null \
  || fail "major Actions must be one group per repository, never automerged"

# 3. Automerge classes (r617).
# Every automerge: true anywhere in the preset sits in exactly the three class rules below; nothing
# else (top-level, update-type objects such as major/minor, lockFileMaintenance) may turn it on.
[ "$(jq '[.. | objects | select(.automerge == true)] | length' $d)" = "3" ] \
  || fail "automerge: true must appear exactly three times (class C, class B tooling, class B Actions)"
[ "$(jq '[.packageRules[] | select(.automerge == true)] | length' $d)" = "3" ] \
  || fail "automerge: true is allowed only inside packageRules"

# Each class rule: scoped to exactly one class list, non-major only, merged by Renovate itself after
# every check run is green (platformAutomerge off: GitHub's auto-merge waits only for required checks).
jq -e --argjson B "$B" --argjson C "$C" --argjson nm "$NON_MAJOR" '
  [.packageRules[] | select(.automerge == true)]
  | all(
      ((.matchRepositories // [] | sort) as $r | $r == $B or $r == $C)
      and (.matchUpdateTypes // [] | length > 0)
      and ((.matchUpdateTypes | sort) - $nm | length == 0)
      and .automergeType == "pr"
      and .platformAutomerge == false
    )' $d >/dev/null \
  || fail "an automerge rule is outside classes B and C, allows major, or merges without all checks"

# Class C: one rule, the whole weekly group of the C repositories, GitHub Actions excluded.
jq -e --argjson C "$C" '
  [.packageRules[] | select(.automerge == true and ((.matchRepositories // []) | sort) == $C)]
  | length == 1 and (.[0].matchManagers == ["!github-actions"])
    and ((.[0] | keys) - ["description","matchRepositories","matchManagers","matchUpdateTypes","automerge","automergeType","platformAutomerge"] | length == 0)' $d >/dev/null \
  || fail "class C must be one rule over the C repositories that excludes github-actions and matches nothing narrower or wider"

# Class B: exactly two rules, the tooling group and the Actions.
jq -e --argjson B "$B" --argjson T "$T" --argjson dev "$DEV_DEP_TYPES" '
  [.packageRules[] | select(.automerge == true and ((.matchRepositories // []) | sort) == $B)] as $rules
  | ($rules | length == 2)
    and ([$rules[] | select(.groupSlug == "weekly-tooling"
          and .groupName == "weekly tooling"
          and ((.matchPackageNames // []) | sort) == $T
          and ((.matchDepTypes // []) | sort) == $dev
          and (.matchUpdateTypes | sort) == ["minor","patch"])] | length == 1)
    and ([$rules[] | select(.matchManagers == ["github-actions"] and .matchDepTypes == ["action"] and (has("groupName") | not))] | length == 1)' $d >/dev/null \
  || fail "class B must be the tooling group (exact name list, dev dependency types) and the Actions rule (depType action only)"

# What the github-actions manager finds besides Actions (runtime versions in with:, service, container
# and runner images) gets its own PR without automerge in class B, after the Actions rule.
jq -e --argjson B "$B" '
  .packageRules as $p
  | ([range(0; $p | length) | select($p[.].automerge == true and $p[.].matchManagers == ["github-actions"])] | max) as $on
  | ([range(0; $p | length) | select($p[.].groupSlug == "github-actions-versions")]) as $v
  | ($v | length == 1)
    and ($p[$v[0]].automerge == false)
    and ($p[$v[0]].matchManagers == ["github-actions"])
    and ($p[$v[0]].matchDepTypes == ["!action"])
    and ((($p[$v[0]].matchRepositories // []) | sort) == $B)
    and ($v[0] > $on)' $d >/dev/null \
  || fail "non-Action dependencies of github-actions in class B must be a later group without automerge"

# The tooling group holds only names from the list, wherever it is set.
jq -e --argjson T "$T" '
  [.packageRules[] | select(.groupSlug == "weekly-tooling" or .groupName == "weekly tooling")]
  | all(((.matchPackageNames // []) | sort) == $T and ((.matchPackageNames // []) | length > 0))' $d >/dev/null \
  || fail "the weekly tooling group may hold only the names of the tooling list"

# Actions in workflows that deploy or write: never automerged, and the rule comes after the class B
# Actions rule so it wins (later package rules override earlier ones).
jq -e --argjson B "$B" '
  .packageRules as $p
  | ([range(0; $p | length) | select($p[.].automerge == true and $p[.].matchManagers == ["github-actions"])] | max) as $on
  | ([range(0; $p | length) | select($p[.].groupSlug == "github-actions-deploy")]) as $off
  | ($off | length == 1)
    and ($p[$off[0]].automerge == false)
    and ($p[$off[0]].matchManagers == ["github-actions"])
    and ((($p[$off[0]].matchRepositories // []) | sort) == $B)
    and (($p[$off[0]].matchFileNames // []) | length > 0)
    and ($off[0] > $on)' $d >/dev/null \
  || fail "Actions in deploying workflows must be a later rule with automerge false"

# Digest pin of the last FROM only for versioned tags (an unversioned tag has no release timestamp,
# so the 7-day rule would hold its digest updates forever).
jq -e '[.packageRules[] | select(.pinDigests == true)] | length == 1
  and (.[0].matchManagers == ["dockerfile"]) and (.[0].matchDepTypes == ["final"]) and (.[0].matchCurrentValue == "/^\\d/")' $d >/dev/null \
  || fail "pinDigests must cover only the final stage of a Dockerfile with a versioned tag"

# lockfile.json and github-binaries.json never automerge.
for f in lockfile.json github-binaries.json; do
  [ "$(jq '[.. | objects | select(.automerge == true)] | length' "$f")" = "0" ] || fail "$f must not automerge"
done
[ "$(jq -r '.lockFileMaintenance.automerge' lockfile.json)" = "false" ] || fail "lockfile preset must not automerge"

echo "OK"
