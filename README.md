# sofka for openSUSE

Repackages [sofka](https://sofka.rs)'s official Linux release tarballs
(`x86_64`/`aarch64`, `gnu` target) into a native **RPM for openSUSE**,
built and GPG-signed by the [Open Build Service](https://build.opensuse.org)
project [`home:hierynomus`](https://build.opensuse.org/package/show/home:hierynomus/sofka).

sofka is a keyboard-first, evidence-based Kubernetes TUI — "a Kubernetes
TUI that tells you why it's broken" — built on
[kube-rs](https://kube.rs) and [ratatui](https://ratatui.rs). Upstream:
[nklmilojevic/sofka](https://github.com/nklmilojevic/sofka).

## Install

```sh
sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
sudo zypper refresh
sudo zypper install sofka
```

x86_64 and aarch64.

## How it works

The package source **is this repo**. OBS mirrors `packaging/` via
`<scmsync>` and rebuilds when a push changes it. Upstream's release
tarballs are never committed: `packaging/_service` fetches both the
x86_64 and aarch64 tarballs at build time, and
`packaging/sofka.spec` verifies the one it needs (`%ifarch`) against its
SHA256 from upstream's release `SHA256SUMS`.

The tarball itself is just a stripped, statically-featured release binary
plus license/attribution files — no compilation happens here.

| path | what |
|---|---|
| `packaging/sofka.spec` | the recipe — `%prep` checksum per arch, install the binary + license docs |
| `packaging/sofka-rpmlintrc` | rpmlint filters for upstream-inherent / deliberate findings |
| `packaging/_service` | `download_url` for each arch's upstream tarball |
| `.obs/workflows.yml` | OBS SCM/CI — build each PR in a scratch project, report status back |
| `.github/workflows/upstream-bump.yml` | daily — open a PR when upstream publishes a newer release |
| `scripts/bump-version.sh` | rewrite `packaging/` from upstream's GitHub release (no tarball download) |
| `scripts/local-build.sh` | fetch the host-arch tarball + `rpmbuild -bb` locally, to test before OBS |
| `scripts/obs-bootstrap.sh` | one-time OBS setup (adds aarch64, `:ci` project, `<scmsync>`, runservice token) |
| `docs/obs-setup.md` | the one-time token + webhook steps |

## Update flow

1. `upstream-bump.yml` (or `scripts/bump-version.sh` by hand) opens a PR
   bumping `Version` + both `%global sofka_sha256_*` + the `_service` URLs.
2. OBS test-builds the PR (both arches); the status checks land on it.
3. Merge → OBS re-syncs and rebuilds `home:hierynomus/sofka`.

## Local build

```sh
scripts/local-build.sh        # -> ./dist/sofka-*.rpm (host arch)
```

Needs `rpm-build`. Same `%prep` checksum gate as OBS.

## One-time OBS wiring

See [`docs/obs-setup.md`](docs/obs-setup.md): run `scripts/obs-bootstrap.sh`,
create a GitHub PAT and the `workflow` token, then add two GitHub webhooks
(push → `/trigger/webhook`, PR → `/trigger/workflow`).

## Notes

- Unsigned local builds: `sudo zypper --no-gpg-checks install ./dist/*.rpm`,
  or add the OBS repo (signed) as above.
- `License:` is `MIT OR Apache-2.0`, matching upstream's own dual license.
  The RPM also ships upstream's aggregated third-party license/attribution
  files (`RUST-LICENSES.html`, `THIRD-PARTY-LICENSES.txt`) as `%doc`.
- Only the plain `gnu`-target tarballs are used (not `musl`) — glibc is
  always present on openSUSE, and rpm's dependency generator picks up the
  binary's small dynamic dependency (glibc/libgcc) automatically; no
  manual `Requires:` needed.

## License

The packaging in this repo (spec, `_service`, scripts, CI config) is
[MIT](LICENSE). It does not contain or redistribute sofka itself — the
binary is upstream's, fetched from their GitHub releases at build time.
