# Pacto Actions

GitHub Action for the [Pacto](https://trianalab.github.io/pacto/) CLI — an OCI-distributed contract standard for cloud-native services.

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install the Pacto CLI |
| `diff` | Compare contracts and detect breaking changes |
| `push` | Push contracts to an OCI registry |

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
| `github-token` | GitHub token for API requests to avoid rate limiting | No | `${{ github.token }}` |

### Outputs

| Name | Description |
|------|-------------|
| `version` | The exact version that was installed |

## Diff

Compares two contracts and classifies changes as non-breaking or potentially breaking.

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: diff
    old: ./contracts/v1
    new: ./contracts/v2
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `old` | Baseline contract: directory path or `oci://` reference | Yes | — |
| `new` | Updated contract: directory path or `oci://` reference | Yes | — |
| `output-format` | Output format: `text` or `json` | No | `text` |
| `fail-on-breaking` | Fail the action if breaking changes are detected | No | `true` |

> **Note on `oci://` prefix:** The `diff` command accepts `oci://` prefixed references for remote contracts (e.g., `oci://ghcr.io/my-org/my-service:v1.0.0`). The `push` command does **not** use this prefix — provide bare registry references instead (e.g., `ghcr.io/my-org/my-service:v1.0.0`).

### Outputs

| Name | Description |
|------|-------------|
| `has-breaking-changes` | `true` if breaking changes were detected |
| `diff-output` | The full diff output |

## Push

Pushes validated contracts to an OCI registry.

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: ghcr.io/my-org/my-service:v1.0.0
    path: ./contracts/my-service
```

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `ref` | OCI reference (e.g., `ghcr.io/org/name:tag`) | Yes | — |
| `path` | Path to contract directory | No | `.` |
| `registry` | Registry hostname for authentication | No | — |
| `username` | Registry username | No | — |
| `password` | Registry password or token | No | — |

### Authentication

#### GitHub Container Registry (GHCR)

Your workflow (or job) **must** declare `packages: write` permission for the `GITHUB_TOKEN` to have write access to GHCR:

```yaml
jobs:
  push-contracts:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - uses: trianalab/pacto-actions@v1
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          command: push
          ref: ghcr.io/my-org/my-service:v1.0.0
          path: ./contracts/my-service
```

Pacto detects GHCR credentials from the `GH_TOKEN` environment variable via the GitHub CLI. This works when the `GITHUB_TOKEN` has the `write:packages` scope.

**Troubleshooting GHCR permission errors:** If you see `permission_denied: write_package`, the `GITHUB_TOKEN` may lack access to the package. This happens when the GHCR package was originally created by a different user or token. To fix it:

1. Go to the package settings on GitHub: `https://github.com/orgs/<org>/packages/container/<package>/settings`
2. Under **Manage Actions access**, add the repository and grant it **Write** role.
3. Alternatively, delete the existing package and let the workflow recreate it — the new package will inherit the correct permissions.

If auto-detection does not work for your setup, you can also authenticate explicitly with GHCR:

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: ghcr.io/my-org/my-service:v1.0.0
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
    ref: registry.example.com/my-service:v1.0.0
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
    paths: ['contracts/**']
  pull_request:
    paths: ['contracts/**']

permissions:
  packages: write  # required for GHCR push

jobs:
  contracts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install the Pacto CLI
      - uses: trianalab/pacto-actions@v1
        with:
          command: setup

      # Extract version from pacto.yaml for tagging
      - name: Extract contract version
        id: contract
        run: |
          VERSION=$(grep '^version:' ./contracts/my-service/pacto.yaml | awk '{print $2}')
          echo "version=${VERSION}" >> "$GITHUB_OUTPUT"

      # Compare against the currently published contract
      - uses: trianalab/pacto-actions@v1
        with:
          command: diff
          old: oci://ghcr.io/my-org/my-service:latest
          new: ./contracts/my-service

      # Push on merge to main
      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          command: push
          ref: ghcr.io/my-org/my-service:${{ steps.contract.outputs.version }}
          path: ./contracts/my-service
```

### Notes on this example

- **`permissions: packages: write`** is required at the workflow or job level for the `GITHUB_TOKEN` to push to GHCR. Without it, pushes fail regardless of authentication method.
- **Version extraction** reads the `version` field from `pacto.yaml` so the OCI tag matches the contract version. Adjust the `grep`/`awk` command to match your `pacto.yaml` structure, or use [`yq`](https://github.com/mikefarah/yq) for more robust YAML parsing: `yq '.version' ./contracts/my-service/pacto.yaml`.
- **`oci://` prefix** is used in `diff` to reference remote contracts. The `push` command takes bare registry refs without the `oci://` prefix.
- **First-time GHCR push:** If the package does not exist yet, the first push creates it. If a package already exists and was created by a different token, see the [GHCR troubleshooting section](#github-container-registry-ghcr) above.

## License

[MIT](LICENSE)
