# renovate-config

Shared [Renovate](https://docs.renovatebot.com/) presets for the Sinimus repositories. Every repository carries the same `renovate.json`; what differs between repositories lives here.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>Sinimus/renovate-config"]
}
```

## Presets

| Preset | Extends as | Purpose |
|---|---|---|
| `default.json` | `github>Sinimus/renovate-config` | Schedule, grouping, 7-day release age, pinned Actions, automerge by class (B, C) |
| `lockfile.json` | `github>Sinimus/renovate-config:lockfile` | Monthly lock file maintenance for pnpm and uv, opt-in per repository |
| `github-binaries.json` | `github>Sinimus/renovate-config:github-binaries` | Opt-in: binaries and npm tools pinned as `ARG` lines in a Dockerfile, see below |

## Binaries pinned in a Dockerfile (`github-binaries.json`)

Two regex managers for any `Dockerfile`. A GitHub release asset is pinned as a comment and two `ARG` lines, raised together (version and sha256 of the asset):

```dockerfile
# renovate: datasource=github-release-attachments depName=hetznercloud/cli
ARG HCLOUD_VERSION=v1.70.2
ARG HCLOUD_SHA256=<64 hex characters>
```

The version must be the release tag exactly, with its `v` where the project uses one: Renovate looks the digest up under `releases/tags/<version>` and silently skips the update when that tag does not exist. An npm tool installed in the image is pinned the same way with `datasource=npm` and only the `_VERSION` line. Both datasources carry release timestamps, so the 7-day rule of `default.json` applies. The preset comes from the konzole repository (PR #73, 30 October 2026), where `--dry-run=extract` found all 12 pinned binaries.

## What `default.json` does

| Setting | Value | Note |
|---|---|---|
| Schedule | Monday 05:00 to 08:59, `Europe/Prague` | Cron `* 5-8 * * 1`; `updateNotScheduled: false` keeps existing PRs still outside the window |
| Grouping | One PR "weekly updates" per repository for minor, patch, digest and pin updates | Major updates stay one PR per dependency; monorepo groups from `config:recommended` still apply |
| Release age | `minimumReleaseAge: "7 days"`, `internalChecksFilter: "strict"` | No branch or PR exists until the version is 7 days old |
| Security fixes | `vulnerabilityAlerts` with `minimumReleaseAge: "2 days"` and `automerge: false` | Raised on any day (they skip schedule and limits), in their own PR, for versions at least 2 days old; never merged by Renovate (owner's ruling r616, 30 October 2026) |
| OSV | `osvVulnerabilityAlerts: true` | Vulnerability PRs from the OSV database for direct dependencies (npm, PyPI, Go and others), in place of GitHub Dependabot alerts; OSV also makes Renovate skip updates flagged as malicious |
| GitHub Actions | `helpers:pinGitHubActionDigests`, own group `github-actions`, majors in `github-actions major` | `uses: owner/action@<sha> # v4`; non-major Action updates come in a separate weekly PR, so a PR either touches `.github/` or does not; every major update the github-actions manager finds (Actions, runner images such as `ubuntu-26.04`, runtime versions in `with:`) comes in one PR per repository |
| Docker | `dockerfile` and `docker-compose` managers of `config:recommended` | Tags are updated. The last `FROM` of a Dockerfile is pinned to its digest when its tag is versioned (`node:24-alpine`, not `nginx:stable-alpine`), see below. GHCR has no release timestamps, so digest updates of `ghcr.io/sinimus/**` (own CI images) skip the 7-day rule; third-party GHCR images keep it |
| Automerge | Only classes B and C below | Top-level `automerge: false`; three package rules turn it on, each for a fixed list of repositories (owner's ruling r617, 31 October 2026) |
| Concurrency | `prConcurrentLimit: 5` | Bounds CI minutes on a first run |

## Automerge classes (ruling r617)

An update merges itself only when it passes **A** and then **B** or **C**. Everything else, and every update in a repository on neither list, is merged by hand.

**A, always.** A `minor`, `patch`, `pin`, `digest` or `pinDigest` update, never `major`; not a security update (`vulnerabilityAlerts` sets `automerge: false` and Renovate applies it as the last rule); 7 days old (`minimumReleaseAge`, `internalChecksFilter: "strict"`); and every check run on the branch green. `platformAutomerge: false` makes Renovate merge the PR itself after reading all check runs; GitHub's own auto-merge would wait only for the checks a ruleset marks as required. A repository without any workflow on `pull_request` never gets a green branch (Renovate reports "yellow" when there are no check runs) and so never automerges.

**B, tooling in repositories that do not deploy on merge**: `konzole`, `unraid-scripts`, `rag-service`, `nanoclaw`, `kuzu-mcp-server`.

- npm `devDependencies` and uv `dependency-groups` / `tool.uv.dev-dependencies` whose name is on the list: `eslint`, `@eslint/**`, `eslint-*`, `typescript-eslint`, `@typescript-eslint/**`, `prettier`, `prettier-plugin-*`, `@types/**`, `vitest`, `@vitest/**`, `jest`, `@jest/**`, `jest-*`, `@testing-library/**`, `@playwright/test`, `husky`, `lint-staged`, `knip`, `ruff`, `mypy`, `pytest`, `pytest-*`, `types-*`. They come in their own weekly PR, `weekly tooling`. The boundary is the name, not the dependency type: `vite`, `tailwindcss` or `typescript` are dev dependencies that change what is built, so they are not on the list.
- GitHub Actions (`uses: owner/action`, depType `action`) in the `github-actions` PR. Runtime versions passed in `with:`, service and container images and runner images are found by the same manager but are not Actions; they come in `github-actions versions` and are merged by hand (in `rag-service` the Qdrant image of the integration job mirrors production on purpose).
- Actions in workflows that deploy, publish or write to the repository (`deploy*`, `release*`, `*publish*`, `docker-build`, `ci-cd`, `pipeline`, `bump-version`, `update-tokens`, `label-pr`) come in `github-actions deploy` and are merged by hand. None of the five repositories deploys today; the list keeps that true if one starts to.

**C, the whole weekly group in repositories with browser tests before deploy**: `jotl-companion`, `hegemony-companion-app`, `gwt-new_zealand-companion`, `root-companion`. Their pull requests build the production image from the Dockerfile that deploys, start it, open every page of `e2e/routes.json` in headless Chromium and fail on `pageerror` or `console.error`; the deploy job needs those checks. GitHub Actions are excluded in class C, because every workflow of these repositories is part of the deploy. `stationfall-companion-app` joins once its browser test is merged.

Renovate merges only inside the schedule window (Monday 05:00 to 08:59). With `updateNotScheduled: false` the branch worker stops at the schedule check before it reaches the merge step (`lib/workers/repository/update/branch/index.ts`), so a PR whose checks turn green after the last run of the window waits for the next Monday.

Renovate merges a group only when every update in it may automerge (`lib/workers/repository/updates/generate.ts`, `config.automerge = upgrades.every(...)`), which is why class B needs its own groups.

**Adding a repository or a tool** takes one line in `default.json` and one in `scripts/check.sh`, in one PR. `check.sh` holds the same lists and fails when they differ.

### Digest of the last `FROM`

The final stage of a Dockerfile is pinned to its digest when the tag starts with a digit (`matchCurrentValue: "/^\\d/"`). Pinning makes the base image move only through a PR that waited 7 days; an unpinned base is whatever the registry serves at build time, with no age check at all. Docker Hub gives each tag a release time (`tag_last_pushed`), and Renovate ages a digest update by the time of the newest version the tag matches. An unversioned tag such as `nginx:stable-alpine` matches no version, so it has no timestamp: under the default `minimumReleaseAgeBehaviour: "timestamp-required"` its digest updates would wait forever, and the pin would freeze the base. Those tags stay unpinned until the repository moves to a versioned tag (`nginx:<major>.<minor>-alpine` instead of `nginx:stable-alpine`). Source: `lib/workers/repository/process/lookup/index.ts` and `lookup/digest.ts` (`applyMinimumReleaseAgeToDigestUpdate`), Renovate 44.198.

## Behaviour that is not obvious

- **Security updates skip `minimumReleaseAge` by default.** Renovate's `vulnerabilityAlerts` object ships with `minimumReleaseAge: null`; this config sets it to 2 days. Renovate applies `vulnerabilityAlerts` as the last package rule of each alert, so its `automerge: false` wins over classes B and C. Renovate also needs the Dependency graph and Dependabot alerts enabled on the repository, and `read` access to Dependabot alerts for the app, otherwise no security PR is raised. An urgent fix can be forced from the Dependency Dashboard.
- **Renovate does not pass its release age to pnpm or uv.** For npm it adds `--before`, for pnpm and uv it does nothing, and lock file maintenance is not enforced at all. The age holds for direct dependencies Renovate itself bumps. Transitive versions are chosen by pnpm or uv when they rewrite the lock file, so the repository needs its own guard: `minimumReleaseAge` in `pnpm-workspace.yaml`, `exclude-newer = "7 days"` under `[tool.uv]` in `pyproject.toml`. That is why `lockfile.json` is a separate preset and not part of `default.json`.
- **The 2-day fast path and the repositories' own 7-day guards.** Docker tags, GitHub Actions and the `github-binaries` pins have no guard of their own, so 2 days apply directly. In a pnpm repository Renovate writes the exception itself: a security PR adds `<package>@<version>` under `minimumReleaseAgeExclude` in `pnpm-workspace.yaml` with the comment `Renovate security update` (`lib/modules/manager/npm/artifacts.ts`, `updatePnpmWorkspace`; seen in upol_knowledge_hub #78, 30 October 2026). Read that line in review; the entry stays after the merge until it is removed by hand once the version is 7 days old. uv has no such step: `exclude-newer` refuses a version younger than 7 days and the security PR fails to update `uv.lock`. A uv fix that cannot wait goes in by hand: a PR with a per-package `exclude-newer-package`, after reading the diff and provenance of the new version, merged by the owner and never automerged, the exception removed at day 7.
- **Update types without a release timestamp** (`lockFileMaintenance`, `lockfileUpdate`, `replacement`, `pin`, `bump`, `rollback`) have the age check switched off, as in Renovate's own `security:minimumReleaseAge*` presets. Left on, they would wait forever. `pinDigest` is switched off too: pinning an Action to the commit its tag already points at is safer than leaving it floating.
- **Registries without release timestamps** (GHCR, Quay, ECR) hold digest updates indefinitely under the default `minimumReleaseAgeBehaviour: "timestamp-required"`. Docker Hub, npm, PyPI and GitHub tags have timestamps. No image of ours is based on GHCR; if one is, add a package rule for it with `minimumReleaseAgeBehaviour: "timestamp-optional"`.

## Checks

`scripts/check.sh` runs `renovate-config-validator --strict` on the three presets (through `pnpm dlx`, Node 24) and asserts the invariants above with `jq`: 7 days for updates and 2 days without automerge for security fixes, strict filter, `automerge: true` exactly three times and only in the class rules, each class rule scoped to exactly its list of repositories, non-major only and merged by Renovate after all checks, the tooling group holding exactly the name list, the rules for deploying workflows and non-Action dependencies coming after the Actions rule, digest pins only for versioned final stages, and lock file maintenance never automerged. `scripts/test-check.sh` breaks one invariant at a time in a copy of the presets and expects `check.sh` to fail on each.

The rules were tried with `renovate --platform=local` (dry-run `lookup`, Renovate 44.181.0) on clones of `jotl-companion` and `root-companion` (class C) and `nanoclaw` and `rag-service` (class B) on 31 October 2026, with the branch config inlined as `renovate.json`. The local platform calls every repository `local`, so the clone's own name in the class list was replaced by `local` for the run. Results, from the branch configs Renovate generated: in class C the `weekly updates` group automerges, while Actions, majors and the pnpm security update (`renovate/npm-pnpm-vulnerability`) do not; in class B `weekly tooling` (eslint, prettier, typescript-eslint, `@types/node`) and the Actions PR automerge, while `weekly updates`, `github-actions versions`, `github-actions deploy`, majors, lock file maintenance and the vitest security update do not. The local platform does not create branches, so the merge itself shows only on a real run.

## Sources

Renovate documentation, checked 30 October 2026 against the `main` branch of `renovatebot/renovate`: `docs/usage/configuration-options.md` (`minimumReleaseAge`, `vulnerabilityAlerts`, `schedule`, `automerge`, `lockFileMaintenance`), `docs/usage/key-concepts/minimum-release-age.md`, `docs/usage/config-presets.md`, `lib/config/presets/internal/security.preset.ts`, `lib/config/options/index.ts` (defaults of `vulnerabilityAlerts`).
