# Packaging

git-workflow doesn't publish to any package repository itself. Every stable release instead
carries recipes a packager can publish as they are, attached to its
[release page](https://github.com/joshua-hvmn/git-workflow/releases) next to the tarball:

| Release asset                            | For            | Rendered from                 |
| ---------------------------------------- | -------------- | ----------------------------- |
| `PKGBUILD`, `PKGBUILD.sig`               | the AUR        | `aur/PKGBUILD.in`             |
| `git-workflow.rb`, `git-workflow.rb.sig` | a Homebrew tap | `homebrew/git-workflow.rb.in` |

The files here are templates, so they never go stale. The release workflow fills in
`@VERSION@` and `@SHA256@` with [`render`](render), checks the result (`bash -n`, `ruby -c`),
and signs each file with the same key as the tarball. Prereleases get none: makepkg allows no
`-` in `pkgver`, and packages follow stable releases.

Why not keep the filled-in recipes on `main`? The tarball's sha256 depends on the release commit
(`git archive` writes the commit's ID into it), so the hash only exists once the release is
tagged. A recipe on `main` would always be one release behind.

Both recipes build from the signed tarball with the Makefile's standard variables
(`make check`, `make PREFIX=... DESTDIR=... install`). Nothing here goes into release tarballs
(see `.gitattributes`). CI renders the PKGBUILD on every push and checks it with
`makepkg --printsrcinfo` and `namcap`, in an Arch container.

## Getting and checking a release's recipes

```sh
v=vX.Y.Z    # the release
base=https://github.com/joshua-hvmn/git-workflow/releases/download/$v
curl -LO "$base/PKGBUILD" -LO "$base/PKGBUILD.sig"
gpg --verify PKGBUILD.sig PKGBUILD   # the key in the README's "Verifying a release"
```

To render them yourself, from a checkout of the release's tag:

```sh
packaging/render "$v" "$(cut -d ' ' -f 1 "git-workflow-$v.tar.gz.sha256")" out/
```

## AUR

For Arch and its derivatives. `check()` runs the full test suite against the tarball, and
makepkg checks the tarball's signature against the primary key in `validpgpkeys`.

First, check that the name is free: <https://aur.archlinux.org/packages/git-workflow>. If it's
taken, change `pkgname` (`_name` stays `git-workflow`, it's the tarball's name).

```sh
gpg --keyserver keyserver.ubuntu.com --recv-keys 4474376DA30B98D6FC34D217348CC5A7E89CC1CD
git clone ssh://aur@aur.archlinux.org/git-workflow.git aur-git-workflow  # a new, empty package
cd aur-git-workflow
# ...download and verify the release's PKGBUILD here (above), then:
makepkg -si                          # build, test, install
namcap PKGBUILD ./*.pkg.tar.zst      # optional lint
makepkg --printsrcinfo >.SRCINFO
git add PKGBUILD .SRCINFO && git commit -m "git-workflow X.Y.Z" && git push
```

Each release: the same, with that release's `PKGBUILD`. It already has `pkgrel=1`; bump
`pkgrel` yourself only for a change to the packaging alone.

## Homebrew

For macOS (and Homebrew on Linux). Homebrew installs formulae from a tap, a repository named
`homebrew-<something>`; with `joshua-hvmn/homebrew-tap` people install with:

```sh
brew install joshua-hvmn/tap/git-workflow
```

Setting the tap up once, with a release's `git-workflow.rb` (downloaded and verified as above):

```sh
gh repo create joshua-hvmn/homebrew-tap --public --clone && cd homebrew-tap
mkdir Formula && cp ../git-workflow.rb Formula/
git add Formula && git commit -m "git-workflow X.Y.Z" && git push
brew install joshua-hvmn/tap/git-workflow && brew test git-workflow
brew audit --strict joshua-hvmn/tap/git-workflow
```

Each release: replace `Formula/git-workflow.rb` with that release's `git-workflow.rb`, then
commit and push.
