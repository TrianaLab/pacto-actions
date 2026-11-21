# Pacto Actions

One reusable step for the [Pacto](https://pacto.run/latest/) CLI on GitHub Actions and GitLab CI/CD. On every pull request it runs `pacto ci` and shows which services change and what each change does to the services that depend on them. On the default branch it runs `pacto ci --publish` and publishes every changed service.

## Table of Contents

- [Quick start](#quick-start)
- [Reusable workflow](#reusable-workflow)
- [GitLab CI/CD](#gitlab-cicd)
- [Composite action](#composite-action)
- [Caching](#caching)
- [Overrides](#overrides)
- [Validate](#validate)
- [Diff](#diff)
- [Doc](#doc)
- [From v1 to v2](#from-v1-to-v2)
- [License](#license)

## Quick start

Add `.github/workflows/pacto.yml`, or let `pacto ci init` write it:

```yaml
on: [pull_request, push]
permissions: {contents: read, packages: write, id-token: write, pull-requests: write}
jobs:
  pacto:
    uses: TrianaLab/pacto-actions/.github/workflows/ci.yml@<commit sha> # v2.0.0
```

Pin the reusable workflow by commit SHA with the tag as a comment, the form Dependabot updates. Add `with: {comment: true}` to post the plan as a pull request comment.

## Reusable workflow

`.github/workflows/ci.yml` runs only `pacto ci`. Pacto detects how each service builds and resolves the registry from the repository (`ghcr.io/<owner>` on GitHub).

### Jobs and permissions

| Job | Runs on | Permissions | What it does |
|-----|---------|-------------|--------------|
| `plan` | `pull_request` | `contents: read`, `packages: read` | Runs `pacto ci`, writes the plan to the job summary, uploads it as the `pacto-plan-md` and `pacto-plan-json` artifacts and annotates the `pacto.yaml` of each changed service: blocked is an error, unverified a warning and clear a notice. |
| `publish` | `push` to the default branch, when `publish` is `true` | `contents: read`, `packages: write`, `id-token: write` | Runs `pacto ci --publish`, one run per repository at a time. |
| `comment` | `pull_request` from the same repository, when `comment` is `true` | `pull-requests: write` | Posts the plan as one comment and updates it on every run. |

The caller grants the full map of the quick start. GitHub checks the permissions of every job of a called workflow before it starts it, skipped jobs included, so a smaller map stops the workflow. Only `publish` holds `id-token: write` and only `comment` writes to a pull request.

Pacto never holds the OIDC token: GitHub mints it for the publish job and Sigstore exchanges it for a short-lived certificate. Keyless signing records the repository, workflow and commit in the public Rekor log; a private repository that must not appear there sets the `sign-key` secret.

GitHub shows at most 10 annotations of each level per step. The job summary holds every row.

### Inputs

| Name | Description | Default |
|------|-------------|---------|
| `path` | Root that `pacto ci` walks for `pacto.yaml` files | `.` |
| `registry` | Registry the services publish to, for example `ghcr.io/acme`. Empty lets `pacto ci` resolve it | `''` |
| `pacto-version` | Pacto release to run. Empty runs the release this version of pacto-actions pins and checks by sha256. `latest` runs the newest release, unpinned | `''` |
| `pacto-artifact` | Name of an artifact of the same run that holds a static linux `pacto` binary; it replaces the download | `''` |
| `publish` | Publish the changed services on a push to the default branch | `true` |
| `comment` | Post the plan as a pull request comment | `false` |
| `fail-on` | `blocked` fails the plan job on exit 1; `unverified` also fails it on exit 2 | `blocked` |
| `transparency-log` | With `sign-key`, record the signatures in the transparency log | `true` |

### Secrets

All secrets are optional. Pass them with `secrets:` in the caller.

| Name | Description |
|------|-------------|
| `registry-username` | Registry user name. GitHub Container Registry needs none |
| `registry-password` | Registry password or token |
| `sign-key` | Cosign private key. `publish` signs with it instead of keyless |
| `sign-key-password` | Password of the cosign key |

### Outputs

| Name | Description |
|------|-------------|
| `gate` | Gate of the plan: `clear`, `blocked` or `unverified` |
| `exit-code` | Exit code of `pacto ci`: `0` clear, `1` blocked, `2` unverified |

### Exit codes

`pacto ci` exits `0` when the plan is clear, `1` when a change is blocked and `2` when Pacto cannot verify a change. With the default `fail-on: blocked`, exit 2 passes the plan job with a warning annotation on every unverified service.

### The pinned Pacto release

Each release of pacto-actions runs one Pacto release, checked against the sha256 of its `pacto_linux_amd64` and `pacto_linux_arm64` assets. A new pacto-actions release, and so a Dependabot bump of your pin, is what moves it. `pacto-version` names another release, checked against that release's `checksums.txt`; `latest` is the unpinned opt-in.

The reusable workflow needs a Pacto release with `pacto ci`. When the pinned release has none, the plan job stops and asks you to set `pacto-version`.

### Builds

GitHub-hosted runners carry Docker and Buildx, so services that build from a Dockerfile or with Skaffold build in `publish`. Services built with ko, Jib or buildpacks build in your own job and pin the image by digest in their manifest, or run the composite `publish` command in a job you write.

## GitLab CI/CD

Add one entry to `.gitlab-ci.yml`, or let `pacto ci init` add it:

```yaml
include:
  - remote: https://raw.githubusercontent.com/TrianaLab/pacto-actions/<commit sha>/templates/pacto.yml
```

`templates/pacto.yml` is a CI/CD component with two jobs. `pacto-plan` runs `pacto ci` in merge request pipelines and saves `pacto-plan.md` as the `pacto plan` artifact; exit 2 shows the job as passed with a warning. `pacto-publish` runs `pacto ci --publish` on the default branch, one run at a time (`resource_group: pacto-publish`), and is the only job with an ID token (`SIGSTORE_ID_TOKEN`, audience `sigstore`). It pushes to the project's container registry with `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` and builds through a `docker:dind` service, which needs a runner that allows privileged containers.

| Input | Description | Default |
|-------|-------------|---------|
| `path` | Root that `pacto ci` walks | `.` |
| `registry` | Registry the services publish to. Empty uses `CI_REGISTRY_IMAGE` | `''` |
| `pacto-version` | Pacto release to run. Empty runs the pinned release | `''` |
| `image` | Image both jobs run in, pinned by digest. It needs `sh`, `wget` and `sha256sum` | `docker:<version>-cli@sha256:…` |
| `stage-plan` | Stage of `pacto-plan` | `test` |
| `stage-publish` | Stage of `pacto-publish` | `deploy` |

Pass inputs with `inputs:` under the `include:` entry. Both jobs skip the download when the image already ships a `pacto` with `pacto ci`. GitLab instances that block `include:remote` from `raw.githubusercontent.com` copy `templates/pacto.yml` into the instance and include it with `include:local` or `include:project`; the file has no other dependency.

## Composite action

The composite action runs one Pacto command per step, for jobs you write yourself.

| Command | Description |
|---------|-------------|
| `setup` | Install the Pacto CLI |
| `ci` | Plan every service with `pacto ci` |
| `publish` | Publish every changed service with `pacto ci --publish` |
| `impact` | Show which consumers a change affects with `pacto impact` |
| `validate` | Validate a contract against the specification |
| `diff` | Compare contracts and detect breaking changes |
| `doc` | Generate markdown documentation from contracts |

### Setup

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: setup
```

| Name | Description | Default |
|------|-------------|---------|
| `version` | Pacto version to install. Empty installs the pinned release, checked by sha256; `latest` installs the newest release | `''` |
| `github-token` | Token passed as `GH_TOKEN` to all commands (GHCR login, pull request comments, API requests) | `${{ github.token }}` |

Output `version` is the exact version installed.

### CI

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: ci
    registry: ghcr.io/acme # optional
```

Runs `pacto ci` on `path` and sets the outputs `gate` and `exit-code`. The step fails per `fail-on` (`blocked` by default, or `unverified`), the same rule as the reusable workflow; the outputs are set either way.

### Publish

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: publish
```

Runs `pacto ci --publish` on `path` with `registry`. Keyless signing needs `id-token: write` on the job; `pacto ci --publish` refuses to run in a pull request pipeline.

### Impact

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: impact
    old: oci://ghcr.io/acme/payments:1.4.0
    new: ./payments
    output-format: markdown
```

Runs `pacto impact <old> <new>`, sets the output `impact-output` and exits with its code: `0` clear, `1` blocked, `2` unverified.

## Caching

OCI bundles fetched by Pacto are cached locally at `~/.cache/pacto/oci/`. This action automatically persists this cache across workflow runs using `actions/cache`, so repeated references to the same OCI bundles are resolved faster.

Caching is **enabled by default** for all commands that interact with OCI references (`ci`, `publish`, `impact`, `diff`, `doc`). No additional configuration is needed.

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `cache` | Enable OCI bundle caching across workflow runs | No | `true` |

### Disabling the cache

To bypass caching (equivalent to `pacto --no-cache`):

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: diff
    old: oci://ghcr.io/my-org/my-service:v1.0.0
    new: ./pactos/my-service
    cache: 'false'
```

## Overrides

`validate`, `diff` and `doc` support contract value overrides via `values` and `set` inputs. These let you modify contract fields without editing files — useful for environment-specific validation, CI pipelines, and what-if analysis.

| Name | Description | Commands |
|------|-------------|----------|
| `values` | Values file(s) to merge into the contract (newline-separated, last wins) | validate, diff, doc |
| `set` | Set contract values inline (newline-separated, e.g. `service.version=2.0.0`) | validate, diff, doc |
| `old-values` | Values file(s) to merge into the old contract (newline-separated) | diff |
| `old-set` | Set values on the old contract (newline-separated) | diff |
| `new-values` | Values file(s) to merge into the new contract (newline-separated) | diff |
| `new-set` | Set values on the new contract (newline-separated, e.g. `service.version=2.0.0`) | diff |

### Examples

**Validate with environment-specific values:**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: validate
    path: ./pactos/my-service
    values: values/production.yaml
```

**Diff with overrides on the new contract:**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: diff
    old: oci://ghcr.io/my-org/my-service
    new: ./pactos/my-service
    new-set: |
      service.version=2.0.0
      interfaces[0].port=9090
```

**Multiple values files (last wins):**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: validate
    path: ./pactos/my-service
    values: |
      values/defaults.yaml
      values/production.yaml
```

## Validate

Validates a contract against the Pacto specification, checking structural, cross-field, and semantic rules.

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: validate
    path: ./pactos/my-service
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `path` | Contract source: directory path or `oci://` reference | No | `.` |
| `values` | Values file(s) to merge (newline-separated) | No | — |
| `set` | Inline value overrides (newline-separated) | No | — |

## Diff

Compares two contracts and classifies changes as non-breaking or potentially breaking.

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: diff
    old: ./pactos/v1
    new: ./pactos/v2
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `old` | Baseline contract: directory path or `oci://` reference | Yes | — |
| `new` | Updated contract: directory path or `oci://` reference | Yes | — |
| `output-format` | Output format: `text`, `json`, or `markdown` | No | `text` |
| `fail-on-breaking` | Fail the action if breaking changes are detected | No | `true` |
| `comment-on-pr` | Post the diff results as a PR comment | No | `false` |
| `values` | Values file(s) to merge into both contracts (newline-separated) | No | — |
| `set` | Inline value overrides for both contracts (newline-separated) | No | — |
| `old-values` | Values file(s) to merge into the old contract (newline-separated) | No | — |
| `old-set` | Inline value overrides for the old contract (newline-separated) | No | — |
| `new-values` | Values file(s) to merge into the new contract (newline-separated) | No | — |
| `new-set` | Inline value overrides for the new contract (newline-separated) | No | — |

> **`oci://` prefix:** All commands that accept OCI references use the `oci://` prefix consistently (e.g., `oci://ghcr.io/my-org/my-service:v1.0.0`). This applies to `diff`, `impact`, `doc` and any other command that references remote contracts.

### Outputs

| Name | Description |
|------|-------------|
| `has-breaking-changes` | `true` if breaking changes were detected |
| `diff-output` | The full diff output |

## Doc

Generates markdown documentation from contracts.

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: doc
    path: ./pactos/my-service
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `path` | Contract source: directory path or `oci://` reference | No | `.` |
| `output-path` | File path to save the generated markdown (e.g., `docs/contract-api.md`) | No | — |
| `comment-on-pr` | Post the documentation as a PR comment | No | `false` |
| `add-to-summary` | Add the documentation to the GitHub Step Summary | No | `true` |
| `values` | Values file(s) to merge (newline-separated) | No | — |
| `set` | Inline value overrides (newline-separated) | No | — |

### Outputs

| Name | Description |
|------|-------------|
| `doc-output` | The generated markdown documentation |

> **Note:** The `path` input defaults to `.`, which expects a `pacto.yaml` file in the repository root. Ensure `path` points to a directory containing a valid `pacto.yaml` file.

> **CLI vs action inputs:** When using the CLI directly in a `run:` step, use `pacto doc <path> -o <directory>`. The CLI's `-o` flag accepts a **directory**, while the action's `output-path` input accepts a specific **file path**. Do not confuse the two when mixing action steps with `run:` steps.

### Examples

**Save documentation to a file:**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: doc
    path: ./pactos/my-service
    output-path: ./docs/contract-api.md
```

**Post documentation as a PR comment:**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: doc
    path: ./pactos/my-service
    comment-on-pr: 'true'
```

> **Note:** The `comment-on-pr` option requires `pull-requests: write` permission for the `GITHUB_TOKEN`. The comment is idempotent — re-runs update the existing comment instead of creating duplicates. Each action invocation with a different `path` creates and manages its own independent PR comment, so 3 invocations for 3 services will produce 3 separate PR comments.

**Generate documentation from an OCI reference:**

```yaml
- uses: trianalab/pacto-actions@v2
  with:
    command: doc
    path: oci://ghcr.io/my-org/my-service:v1.0.0
```

## From v1 to v2

- `push` is gone. Declare `publish.bundle` in `pacto.yaml` and let `pacto ci --publish` publish: it raises the version, builds, signs and publishes every changed service. The `ref`, `username` and `password` inputs went with it.
- `setup` installs the pinned Pacto release by default, checked by sha256. Set `version: latest` to keep v1's behaviour.
- One reusable workflow replaces the install, validate, diff and push steps. See [Quick start](#quick-start).
- `v1` stays at v1.x.

## License

[MIT](LICENSE)
