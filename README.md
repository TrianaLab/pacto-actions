# Pacto Actions

GitHub Action for the [Pacto](https://trianalab.github.io/pacto/) CLI — an OCI-distributed contract standard for cloud-native services.

## Table of Contents

- [Commands](#commands)
- [Setup](#setup)
- [Caching](#caching)
- [Validate](#validate)
- [Diff](#diff)
- [Doc](#doc)
- [Push](#push)
  - [Authentication](#authentication)
- [Full CI/CD Example](#full-cicd-example)
- [Multi-Service Workflow](#multi-service-workflow)
- [License](#license)

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install the Pacto CLI |
| `validate` | Validate a contract against the specification |
| `diff` | Compare contracts and detect breaking changes |
| `push` | Push contracts to an OCI registry |
| `doc` | Generate markdown documentation from contracts |

## Setup

Downloads and installs the Pacto CLI binary.

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: setup
    version: v0.2.1 # optional, defaults to latest
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `version` | Pacto version to install (e.g., `v0.2.1`) | No | `latest` |
| `github-token` | GitHub token passed as `GH_TOKEN` to all commands (used for GHCR auth, PR comments, API requests) | No | `${{ github.token }}` |

### Outputs

| Name | Description |
|------|-------------|
| `version` | The exact version that was installed |

## Caching

OCI bundles fetched by Pacto are cached locally at `~/.cache/pacto/oci/`. This action automatically persists this cache across workflow runs using `actions/cache`, so repeated references to the same OCI bundles are resolved faster.

Caching is **enabled by default** for all commands that interact with OCI references (`diff`, `doc`, `push`). No additional configuration is needed.

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `cache` | Enable OCI bundle caching across workflow runs | No | `true` |

### Disabling the cache

To bypass caching (equivalent to `pacto --no-cache`):

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: diff
    old: oci://ghcr.io/my-org/my-service:v1.0.0
    new: ./pactos/my-service
    cache: 'false'
```

## Validate

Validates a contract against the Pacto specification, checking structural, cross-field, and semantic rules.

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: validate
    path: ./pactos/my-service
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `path` | Contract source: directory path or `oci://` reference | No | `.` |

## Diff

Compares two contracts and classifies changes as non-breaking or potentially breaking.

```yaml
- uses: trianalab/pacto-actions@v1
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

> **`oci://` prefix:** All commands that accept OCI references use the `oci://` prefix consistently (e.g., `oci://ghcr.io/my-org/my-service:v1.0.0`). This applies to `diff`, `push`, `doc`, and any other command that references remote contracts.

### Outputs

| Name | Description |
|------|-------------|
| `has-breaking-changes` | `true` if breaking changes were detected |
| `diff-output` | The full diff output |

## Doc

Generates markdown documentation from contracts.

```yaml
- uses: trianalab/pacto-actions@v1
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

### Outputs

| Name | Description |
|------|-------------|
| `doc-output` | The generated markdown documentation |

> **Note:** The `path` input defaults to `.`, which expects a `pacto.yaml` file in the repository root. Ensure `path` points to a directory containing a valid `pacto.yaml` file.

> **CLI vs action inputs:** When using the CLI directly in a `run:` step, use `pacto doc <path> -o <directory>`. The CLI's `-o` flag accepts a **directory**, while the action's `output-path` input accepts a specific **file path**. Do not confuse the two when mixing action steps with `run:` steps.

### Examples

**Save documentation to a file:**

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: doc
    path: ./pactos/my-service
    output-path: ./docs/contract-api.md
```

**Post documentation as a PR comment:**

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: doc
    path: ./pactos/my-service
    comment-on-pr: 'true'
```

> **Note:** The `comment-on-pr` option requires `pull-requests: write` permission for the `GITHUB_TOKEN`. The comment is idempotent — re-runs update the existing comment instead of creating duplicates. Each action invocation with a different `path` creates and manages its own independent PR comment, so 3 invocations for 3 services will produce 3 separate PR comments.

**Generate documentation from an OCI reference:**

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: doc
    path: oci://ghcr.io/my-org/my-service:v1.0.0
```

## Push

Pushes validated contracts to an OCI registry.

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: oci://ghcr.io/my-org/my-service:v1.0.0
    path: ./pactos/my-service
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `ref` | OCI reference (e.g., `oci://ghcr.io/org/name:tag`) | Yes | — |
| `path` | Path to contract directory | No | `.` |
| `registry` | Registry hostname for authentication | No | — |
| `username` | Registry username | No | — |
| `password` | Registry password or token | No | — |

### Authentication

#### GitHub Container Registry (GHCR)

Your workflow (or job) **must** declare `packages: write` permission for the `GITHUB_TOKEN` to have write access to GHCR:

```yaml
jobs:
  push-pactos:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - uses: trianalab/pacto-actions@v1
        with:
          command: push
          ref: oci://ghcr.io/my-org/my-service:v1.0.0
          path: ./pactos/my-service
```

The action automatically passes `github-token` (defaults to `GITHUB_TOKEN`) as `GH_TOKEN` to all commands — no manual `env` configuration is needed. This works when the `GITHUB_TOKEN` has the `write:packages` scope.

You can override the token via the `github-token` input:

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: oci://ghcr.io/my-org/my-service:v1.0.0
    github-token: ${{ secrets.CUSTOM_TOKEN }}
```

**Troubleshooting GHCR permission errors:** If you see `permission_denied: write_package`, the `GITHUB_TOKEN` may lack access to the package. This happens when the GHCR package was originally created by a different user or token. To fix it:

1. Go to the package settings on GitHub: `https://github.com/orgs/<org>/packages/container/<package>/settings`
2. Under **Manage Actions access**, add the repository and grant it **Write** role.
3. Alternatively, delete the existing package and let the workflow recreate it — the new package will inherit the correct permissions.

If auto-detection does not work for your setup, you can also authenticate explicitly with GHCR:

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: oci://ghcr.io/my-org/my-service:v1.0.0
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

#### Other registries

For non-GHCR registries, provide credentials explicitly:

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: oci://registry.example.com/my-service:v1.0.0
    registry: registry.example.com
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

## Full CI/CD Example

A complete workflow that validates, diffs, and pushes contracts to GHCR:

```yaml
name: Pacto CI
on:
  push:
    branches: [main]
    paths: ['pactos/**']
  pull_request:
    paths: ['pactos/**']

permissions:
  contents: write       # required for committing generated docs
  packages: write       # required for GHCR push
  pull-requests: write  # required for doc PR comments

jobs:
  pactos:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install the Pacto CLI
      - uses: trianalab/pacto-actions@v1
        with:
          command: setup

      # Compare against the currently published contract
      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'pull_request'
        with:
          command: diff
          old: oci://ghcr.io/my-org/my-service
          new: ./pactos/my-service
          fail-on-breaking: 'false'
          comment-on-pr: 'true'

      # Generate and save contract docs
      - uses: trianalab/pacto-actions@v1
        with:
          command: doc
          path: ./pactos/my-service
          output-path: ./docs/my-service-api.md
          comment-on-pr: ${{ github.event_name == 'pull_request' && 'true' || 'false' }}

      # Commit generated docs
      - name: Commit docs
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add docs/
          git diff --cached --quiet || git commit -m "docs: update contract documentation"
          git push

      # Push on merge to main
      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        with:
          command: push
          ref: oci://ghcr.io/my-org/my-service
          path: ./pactos/my-service
```

### Notes on this example

- **`permissions: packages: write`** is required at the workflow or job level for the `GITHUB_TOKEN` to push to GHCR. Without it, pushes fail regardless of authentication method. **`pull-requests: write`** is needed for the `diff` and `doc` commands' `comment-on-pr` feature.
- **`oci://` prefix** is used consistently across all commands (`diff`, `push`, `doc`, etc.) to reference remote contracts. When a tag is omitted, pacto automatically resolves to the highest semver version.
- **First-time GHCR push:** If the package does not exist yet, the first push creates it. If a package already exists and was created by a different token, see the [GHCR troubleshooting section](#github-container-registry-ghcr) above.

## Multi-Service Workflow

When your repository contains multiple contracts (e.g., `pactos/payments-service`, `pactos/users-service`, `pactos/notifications-service`), use **sequential steps in a single job** rather than a matrix strategy. A matrix creates parallel jobs that cause git push race conditions when committing generated docs.

```yaml
name: Pacto CI (Multi-Service)
on:
  push:
    branches: [main]
    paths: ['pactos/**']
  pull_request:
    paths: ['pactos/**']

permissions:
  packages: write
  pull-requests: write
  contents: write

jobs:
  pactos:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: trianalab/pacto-actions@v1
        with:
          command: setup

      # Generate docs for each service sequentially
      - uses: trianalab/pacto-actions@v1
        with:
          command: doc
          path: ./pactos/payments-service
          output-path: ./docs/payments-service-api.md
          comment-on-pr: ${{ github.event_name == 'pull_request' && 'true' || 'false' }}

      - uses: trianalab/pacto-actions@v1
        with:
          command: doc
          path: ./pactos/users-service
          output-path: ./docs/users-service-api.md
          comment-on-pr: ${{ github.event_name == 'pull_request' && 'true' || 'false' }}

      - uses: trianalab/pacto-actions@v1
        with:
          command: doc
          path: ./pactos/notifications-service
          output-path: ./docs/notifications-service-api.md
          comment-on-pr: ${{ github.event_name == 'pull_request' && 'true' || 'false' }}

      # Single commit for all generated docs
      - name: Commit docs
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add docs/
          git diff --cached --quiet || git commit -m "docs: update contract documentation"
          git push

      # Push contracts on merge to main
      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        with:
          command: push
          ref: oci://ghcr.io/my-org/payments-service:latest
          path: ./pactos/payments-service

      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        with:
          command: push
          ref: oci://ghcr.io/my-org/users-service:latest
          path: ./pactos/users-service

      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        with:
          command: push
          ref: oci://ghcr.io/my-org/notifications-service:latest
          path: ./pactos/notifications-service
```

### Notes on this example

- **Sequential steps, not matrix:** A matrix strategy would run parallel jobs, each trying to commit and push docs — causing race conditions. Sequential steps in a single job avoid this.
- **One commit for all docs:** All `output-path` files are staged together and committed once, keeping the git history clean.
- **Separate PR comments:** Each `doc` invocation with `comment-on-pr: 'true'` creates its own independent PR comment, so reviewers see one comment per service.
- **`contents: write`** permission is needed for the commit/push step.

## License

[MIT](LICENSE)
