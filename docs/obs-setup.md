# OBS setup (one-time)

Wires `home:hierynomus/sofka` on build.opensuse.org to this repo. Done
once; after that a push to `main` rebuilds and PRs get test-built.

## Model

- **Package source is this git repo**, via `<scmsync>` in the package meta
  (`obs-scm-bridge`) — no `osc ci`. The `<scmsync>` URL carries
  `?subdir=packaging#main`, so only `packaging/` is packaged; a push that
  doesn't touch `packaging/` regenerates an identical tree and correctly
  does not rebuild.
- **The two release tarballs (~11 MB each) are never in git.**
  `packaging/_service` runs `download_url` at build time for both the
  x86_64 and aarch64 tarballs; `%prep` verifies whichever one the current
  `%ifarch` needs against the SHA256 embedded in the spec.
- **`home:hierynomus` needs an `aarch64` arch** on its
  `openSUSE_Leap_16.0` repository — it only had `x86_64` before sofka
  (that repo also builds claude-desktop, which is `ExclusiveArch: x86_64`
  and is unaffected by adding aarch64). `scripts/obs-bootstrap.sh` adds it.
- **`.obs/workflows.yml`** (repo root) drives **PR builds**: each PR is
  branched into `home:hierynomus:ci:hierynomus:sofka-rpm:PR-<n>`, built
  with publishing disabled, and the result is posted back to the PR as
  status checks (one per arch). The branch project auto-deletes when the
  PR closes.
- **`.github/workflows/upstream-bump.yml`** opens a bump PR when upstream
  ships a newer release. Needs no OBS credentials.

```
GitHub releases (nklmilojevic/sofka) ─(daily cron)→ bump PR ─→ OBS PR build (status checks)
                                            │
                                          merge ─→ push webhook ─→ rebuild ─→
                                            download.opensuse.org/repositories/home:hierynomus/
```

## Steps

### 1. OBS side (scriptable)

```
scripts/obs-bootstrap.sh
```

Idempotent. Adds `aarch64` to `home:hierynomus`'s repository, creates
`home:hierynomus:ci` (the PR branch target, x86_64+aarch64) and sets

```xml
<scmsync>https://github.com/hierynomus/sofka-rpm?subdir=packaging#main</scmsync>
```

on `home:hierynomus/sofka`. It also creates the `runservice` token
(step 3a). By hand: `osc meta pkg home:hierynomus sofka -e`.

### 2. GitHub PAT for OBS

Fine-grained token on `hierynomus/sofka-rpm`:

- **Contents:** read-only
- **Commit statuses:** read/write  (so OBS can report PR build results)

### 3. Two OBS tokens

```
# a) push to main -> re-pull git + rebuild
osc token --create --operation runservice home:hierynomus sofka

# b) PR events -> run .obs/workflows.yml  (feed it the PAT from step 2)
osc token --create --operation workflow --scm-token <GITHUB_PAT>
```

Each prints an **id** and a **secret string**. Two are needed because the
two `/trigger/*` endpoints do different things: `/trigger/webhook`
(runservice) re-pulls the scmsync source and rebuilds; `/trigger/workflow`
only executes `.obs/workflows.yml` steps, which are PR-only.

### 4. Two GitHub webhooks

Repo **Settings → Webhooks → Add webhook**, twice. SSL verification on,
the token **string** in *Secret*, and **Content type: `application/json`
— not the GitHub default.** GitHub's "Add webhook" form defaults to
`application/x-www-form-urlencoded`; it's easy to leave it there since
everything else about the form looks right. `/trigger/workflow` rejects
a form-encoded body outright (`403`, `X-Opensuse-Errorcode: invalid_token`
— indistinguishable at a glance from a wrong secret). `/trigger/webhook`
happens to tolerate form encoding, so if only the PR builds are broken,
check this first before touching the secret.

| Payload URL | Events |
|---|---|
| `https://build.opensuse.org/trigger/webhook?id=<RUNSERVICE_TOKEN_ID>` | Pushes |
| `https://build.opensuse.org/trigger/workflow?id=<WORKFLOW_TOKEN_ID>` | Pull requests |

### 5. GitHub repo setting

**Settings → Actions → General → Workflow permissions:** enable *Allow
GitHub Actions to create and approve pull requests* (for `upstream-bump`).

## Verify

- Ping each webhook (repo **Settings → Webhooks → (hook) → Recent
  Deliveries → Redeliver**, or `gh api -X POST repos/hierynomus/sofka-rpm/hooks/<id>/pings`)
  and confirm `200`.
- Push a commit that changes `packaging/` → `_scmsync.obsinfo` advances and
  a build starts:
  `osc api /source/home:hierynomus/sofka/_scmsync.obsinfo`
- Open a throwaway PR → `OBS SCM/CI Workflow Integration started` appears
  immediately, then `OBS: sofka - openSUSE_Leap_16.0/x86_64` and
  `.../aarch64` land once the scratch build finishes. Close the PR
  afterward; OBS deletes the scratch project on its own.
- Force a sync by hand if ever needed:
  `osc service remoterun home:hierynomus sofka`

## Troubleshooting

- **PR webhook ping returns `403`, body
  `<status code="invalid_token"><summary>No valid token found</summary>`.**
  Reads like a bad secret but usually isn't — first confirm the token is
  actually fine by replaying a self-signed request straight at OBS,
  bypassing GitHub:
  ```sh
  secret=<WORKFLOW_TOKEN_STRING>
  payload='{"zen":"test","repository":{"full_name":"hierynomus/sofka-rpm"}}'
  sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //')
  curl -i -X POST "https://build.opensuse.org/trigger/workflow?id=<WORKFLOW_TOKEN_ID>" \
    -H "Content-Type: application/json" -H "X-GitHub-Event: ping" \
    -H "X-Hub-Signature-256: sha256=$sig" --data "$payload"
  ```
  A `200` here proves the token/project wiring is fine and the problem is
  purely how GitHub is signing its own deliveries — almost always the
  webhook's **Content type** left on `form` instead of `application/json`
  (see step 4). Only chase the secret itself once this replay also fails.

## Install on a machine

```
sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
sudo zypper refresh
sudo zypper install sofka
```
