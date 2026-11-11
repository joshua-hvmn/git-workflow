# Releasing, GitHub flow, and forks

Releasing from `main` in GitHub flow, working on repositories you don't own, the release
workflow `git b pre` and `finish` are built to feed, and checking a release's signature.

## GitHub flow, and repositories you don't own

In GitHub flow nothing pushes to `main`, so it works when `main` only accepts pull requests,
and on repositories where you don't decide how things are set up. `git ps` and `git qc p`
refuse to push a branch that only takes pull requests, and say how to move your commits to a
branch.

```sh
git b start topic fix-typo   # from main, pushed as its own branch
git c fix the typo
git b finish                 # pushes it and opens a pull request into main (gh)
# ...review, merge on GitHub...
git b finish                 # merged: deletes the branch and brings main up to date
```

### Releasing from `main`

A release is a tag, so it doesn't need a push to `main`:

```sh
git b pre              # on main: tags v1.2.0-rc.1 (version from VERSION, or: git b pre v1.2.0)
# ...CI publishes the prerelease; test it...
git b release          # tags the commit rc.1 tested as v1.2.0 and pushes only the tag
```

`git b release` tags the newest prerelease's commit, not whatever `main` has reached by then,
so the release is exactly what you tested; it says how many commits `main` has gained since.
With no prerelease it warns that the release is untested (strict mode refuses). `pre` on `main`
fast-forwards it first, and refuses local commits that aren't on the remote `main`.

### Forks

With a remote named `upstream` (or `workflow.upstream`), `main` and the tags come from
upstream, your branches go to `origin` (your fork), and pull requests go to upstream from your
fork's branch:

```sh
gh repo fork owner/project --clone   # origin is your fork, upstream is owner/project
cd project
git b start topic fix-typo           # from upstream/main, pushed to your fork
git b finish                         # pull request into owner/project from <you>:fix-typo
git sync                             # main from upstream
```

On GitLab (the `gitlab` [forge](configuration.md#forges)) it's the same, with merge requests:
`finish` names your fork as the merge request's head project.

## CI pairing

Designed to feed a tag-triggered release workflow. This repo releases itself with one,
[`.github/workflows/release.yml`](../.github/workflows/release.yml); copy it and change the build step:

- tags containing `-` publish as GitHub prereleases from any branch
- plain `vX.Y.Z` tags are rejected unless the commit is on `main`
- the tag's version must match the `VERSION` file, so bump it on the release branch before
  `git b pre` (`pre` and `finish` check this locally too, before anything is public)
- release notes come from the matching `## vX.Y.Z` section of `CHANGELOG.md`
- the publish job checks the tarball against the hash the build job computed, so a tarball
  that changed in artifact storage is never signed
- a stable release also carries an AUR `PKGBUILD` and a Homebrew formula, filled in with its
  version and the tarball's hash by `packaging/render`, checked the same way, and signed
  ([packaging](../packaging/README.md)); a copy elsewhere can drop the "Packaging recipes" step

The publish job runs in a `release` environment, so a copy of the workflow needs one
(Settings → Environments), with:

- a required reviewer (every release waits for approval) and a deployment tag rule `v*`
- secrets `GPG_PRIVATE_KEY` (an armored signing subkey export) and `GPG_PASSPHRASE`
- variable `GPG_FINGERPRINT` (that subkey's fingerprint), with the primary key published on
  keyserver.ubuntu.com

Before signing, it fetches the published key, so extending the subkey's expiry only needs
`gpg --send-keys`, not a new secret. It fails if the published key can't verify the
signature, and warns 60 days before the key expires.

## Verifying a release

Every release tarball is signed, and its build provenance is attested by GitHub. A stable
release's `PKGBUILD` and `git-workflow.rb` are signed with the same key:
`gpg --verify PKGBUILD.sig PKGBUILD`.

**Primary key**, the one to trust (confirm it somewhere other than this repository):

```
4474 376D A30B 98D6 FC34  D217 348C C5A7 E89C C1CD
```

**Signing subkey**, used only for this repository's releases:

```
 README.md                    |  23 ++++--
1CEA A8B4 D3B8 749E B348  9943 AEA6 4E97 7A5B 316A
```

gpg's "using EDDSA key" line names the signing subkey. Unless you've certified the key, gpg also
warns that it isn't certified and prints both fingerprints: "Primary key fingerprint" should match
the primary key above, and "Subkey fingerprint" the signing subkey. Each repository has its own
subkey, so a compromised one can be revoked without affecting the primary key or other projects.

With `gh` logged in, you can check the provenance instead:
`gh attestation verify git-workflow-vX.Y.Z.tar.gz --repo joshua-hvmn/git-workflow`.
