#
# spec file for package sofka
#
# Copyright (c) 2026 Jeroen van Erp
# Packaging under the MIT License (see LICENSE at the repo root).
#
# sofka itself is MIT OR Apache-2.0; both texts, plus the aggregated
# third-party notices upstream ships alongside the binary, are installed as
# %%doc/%%license below.
#

# SHA256 of each upstream release tarball, taken from the release's
# SHA256SUMS asset. Bumped in lockstep with Version by
# scripts/bump-version.sh. Verified in %%prep so a changed-out-from-under-us
# payload fails the build instead of shipping.
%global sofka_sha256_x86_64  f5e88de54703a98b1bb536c023e9ef96637f51aa36a139c17220fa8ff2f6ed84
%global sofka_sha256_aarch64 2412d7ae80a0cad64085f8206ae91f0888d6b53eeb4df66be6e7aa7bdf9eabab

Name:           sofka
Version:        0.29.2
# OBS supplies the real release (lp160.N.M); 0 is the openSUSE convention.
Release:        0
Summary:        A Kubernetes TUI, reimagined in Rust
License:        MIT OR Apache-2.0
URL:            https://sofka.rs
# Fetched at build time by two download_url source services, one per arch
# (see _service). Kept as bare filenames so OBS does not treat them as
# stored blobs.
Source0:        sofka-v%{version}-x86_64-unknown-linux-gnu.tar.gz
Source1:        sofka-v%{version}-aarch64-unknown-linux-gnu.tar.gz

ExclusiveArch:  x86_64 aarch64

%description
sofka is a keyboard-first, evidence-based Kubernetes TUI: a k9s-alike built
on kube-rs and ratatui, with an "X" command for deterministic incident
views, native Flux CD integration, Helm release inspection, resource
timelines, port forwarding and volume browsing.

Upstream only publishes generic release binaries and packages (deb, rpm,
Arch Linux); this package repackages their official release tarball for
openSUSE.

%prep
# Integrity check: each tarball is fetched over TLS by the download_url
# service; pin it to the checksum published in upstream's release
# SHA256SUMS as well. Only the tarball for the arch being built is present
# as a real download either way (see _service), so all sources are listed
# but only one is extracted per build.
%ifarch x86_64
echo '%{sofka_sha256_x86_64}  %{SOURCE0}' | sha256sum -c -
tar -xzf %{SOURCE0}
%endif
%ifarch aarch64
echo '%{sofka_sha256_aarch64}  %{SOURCE1}' | sha256sum -c -
tar -xzf %{SOURCE1}
%endif

%build
# Nothing to compile: upstream ships a stripped, self-contained release
# binary (dynamically linked only against glibc/libgcc, auto-detected by
# rpm's dependency generator).

%install
install -Dm 0755 sofka %{buildroot}%{_bindir}/sofka

%files
%license LICENSE-MIT LICENSE-APACHE
%doc RUST-LICENSES.html THIRD-PARTY-LICENSES.txt THIRD-PARTY-SOURCES
%{_bindir}/sofka

%changelog
* Fri Sep 25 2026 jeroen <jeroen@hierynomus.com> - 0.29.2-0
- Update to upstream 0.29.2

* Thu Sep 24 2026 jeroen <jeroen@hierynomus.com> - 0.29.1-0
- Update to upstream 0.29.1

* Wed Sep 23 2026 jeroen <jeroen@hierynomus.com> - 0.28.5-0
- Update to upstream 0.28.5

* Tue Sep 22 2026 jeroen <jeroen@hierynomus.com> - 0.28.4-0
- Update to upstream 0.28.4

* Sat Sep 19 2026 jeroen <jeroen@hierynomus.com> - 0.28.3-0
- Update to upstream 0.28.3

* Fri Sep 18 2026 jeroen <jeroen@hierynomus.com> - 0.28.2-0
- Initial packaging: repackage upstream's release tarball as an openSUSE
  RPM, built from git via OBS scmsync. SHA256-verified payload per arch
  (x86_64, aarch64), rpmlint clean.
