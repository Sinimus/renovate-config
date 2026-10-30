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
| `default.json` | `github>Sinimus/renovate-config` | Schedule, grouping, 7-day release age, pinned Actions, automerge allowlist |
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
| Security fixes | `vulnerabilityAlerts` with the same 7 days | Raised on any day (they skip schedule and limits), in their own PR, but only for versions at least 7 days old |
| OSV | `osvVulnerabilityAlerts: true` | Vulnerability PRs from the OSV database for direct dependencies (npm, PyPI, Go and others), in place of GitHub Dependabot alerts; OSV also makes Renovate skip updates flagged as malicious |
| GitHub Actions | `helpers:pinGitHubActionDigests`, own group `github-actions` | `uses: owner/action@<sha> # v4`; non-major Action updates come in a separate weekly PR, so a PR either touches `.github/` or does not |
| Docker | `dockerfile` and `docker-compose` managers of `config:recommended` | Tags are updated, digests are not pinned. GHCR has no release timestamps, so digest updates of `ghcr.io/sinimus/**` (own CI images) skip the 7-day rule; third-party GHCR images keep it |
| Automerge | Allowlist of six simple sites, non-major only, only after green CI | `packageRules` entry with `matchRepositories`; Renovate merges itself (`platformAutomerge: false`) |
| Concurrency | `prConcurrentLimit: 5` | Bounds CI minutes on a first run |

Automerge repositories: `stationfall-companion-app`, `jotl-companion`, `gwt-new_zealand-companion`, `hegemony-companion-app` and `eldritch-horror-companion-app` (plain nginx images with static files), and `root-companion` (a Next.js standalone server, kept on the list by the owner's ruling r508 of 30 October 2026). Everything else is merged by hand, including `hanka-website` (Astro Node server with a Brevo API key for the contact form since 30 October 2026). A new repository is never automerged until it is added to that list in `default.json`.

## Behaviour that is not obvious

- **Security updates skip `minimumReleaseAge` by default.** Renovate's `vulnerabilityAlerts` object ships with `minimumReleaseAge: null`; this config sets it back to 7 days. Renovate also needs the Dependency graph and Dependabot alerts enabled on the repository, and `read` access to Dependabot alerts for the app, otherwise no security PR is raised. An urgent fix can be forced from the Dependency Dashboard.
- **Renovate does not pass its release age to pnpm or uv.** For npm it adds `--before`, for pnpm and uv it does nothing, and lock file maintenance is not enforced at all. The age holds for direct dependencies Renovate itself bumps. Transitive versions are chosen by pnpm or uv when they rewrite the lock file, so the repository needs its own guard: `minimumReleaseAge` in `pnpm-workspace.yaml`, `exclude-newer = "7 days"` under `[tool.uv]` in `pyproject.toml`. That is why `lockfile.json` is a separate preset and not part of `default.json`.
- **Update types without a release timestamp** (`lockFileMaintenance`, `lockfileUpdate`, `replacement`, `pin`, `bump`, `rollback`) have the age check switched off, as in Renovate's own `security:minimumReleaseAge*` presets. Left on, they would wait forever. `pinDigest` is switched off too: pinning an Action to the commit its tag already points at is safer than leaving it floating.
- **Registries without release timestamps** (GHCR, Quay, ECR) hold digest updates indefinitely under the default `minimumReleaseAgeBehaviour: "timestamp-required"`. Docker Hub, npm, PyPI and GitHub tags have timestamps. No image of ours is based on GHCR; if one is, add a package rule for it with `minimumReleaseAgeBehaviour: "timestamp-optional"`.

## Checks

`scripts/check.sh` runs `renovate-config-validator --strict` on both presets (through `pnpm dlx`, Node 24) and asserts the invariants above with `jq`: 7 days in both places, strict filter, exactly one automerge rule, limited to the six repositories and without major updates, lock file maintenance never automerged.

The behaviour was also checked once with `renovate --platform=local --dry-run=lookup` on a clone of `stationfall-companion-app` with `default.json` as its `renovate.json`: updates younger than 7 days were held back (`next` resolved to 16.4.2 instead of the 6-day-old 16.4.3), and `pinDigest` updates appeared for every Action. The local platform does not build branches, so grouping and automerge were not exercised there; they show on the first real run.

## Sources

Renovate documentation, checked 30 October 2026 against the `main` branch of `renovatebot/renovate`: `docs/usage/configuration-options.md` (`minimumReleaseAge`, `vulnerabilityAlerts`, `schedule`, `automerge`, `lockFileMaintenance`), `docs/usage/key-concepts/minimum-release-age.md`, `docs/usage/config-presets.md`, `lib/config/presets/internal/security.preset.ts`, `lib/config/options/index.ts` (defaults of `vulnerabilityAlerts`).
