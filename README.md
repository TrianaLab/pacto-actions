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

For **GitHub Container Registry**, Pacto automatically detects credentials from the GitHub CLI, so explicit login is often unnecessary:

```yaml
- uses: trianalab/pacto-actions@v1
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    command: push
    ref: ghcr.io/my-org/my-service:v1.0.0
```

For **other registries**, provide credentials explicitly:

```yaml
- uses: trianalab/pacto-actions@v1
  with:
    command: push
    ref: registry.example.com/my-service:v1.0.0
    registry: registry.example.com
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

## Full Example

```yaml
name: Pacto CI
on:
  pull_request:
    paths: ['contracts/**']

jobs:
  validate-and-push:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: trianalab/pacto-actions@v1
        with:
          command: setup

      - run: pacto validate ./contracts/my-service

      - uses: trianalab/pacto-actions@v1
        with:
          command: diff
          old: oci://ghcr.io/my-org/my-service:latest
          new: ./contracts/my-service

      - uses: trianalab/pacto-actions@v1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          command: push
          ref: ghcr.io/my-org/my-service
          path: ./contracts/my-service
```

## License

[MIT](LICENSE)
