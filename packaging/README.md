# Packaging

Both packages build from the signed release tarball with the Makefile's standard variables
(`make check`, `make PREFIX=... DESTDIR=... install`). Nothing here goes into release
tarballs (see `.gitattributes`).

## AUR: `aur/PKGBUILD`

For Arch and its derivatives. `check()` runs the full test suite against the tarball, and
makepkg checks the tarball's signature against the primary key in `validpgpkeys`.

First, check that the name is free: <https://aur.archlinux.org/packages/git-workflow>. If it's
taken, change `pkgname` (`_name` stays `git-workflow`, it's the tarball's name).

```sh
gpg --keyserver keyserver.ubuntu.com --recv-keys 4474376DA30B98D6FC34D217348CC5A7E89CC1CD
git clone ssh://aur@aur.archlinux.org/git-workflow.git aur-git-workflow  # a new, empty package
cp packaging/aur/PKGBUILD aur-git-workflow/ && cd aur-git-workflow
makepkg -si                          # build, test, install
namcap PKGBUILD ./*.pkg.tar.zst      # optional lint
makepkg --printsrcinfo >.SRCINFO
git add PKGBUILD .SRCINFO && git commit -m "git-workflow 2.0.0" && git push
```

Each release: set `pkgver`, reset `pkgrel=1`, run `updpkgsums`, then the last four commands
again. Copy the updated PKGBUILD back here.

## Homebrew: `homebrew/git-workflow.rb`

For macOS (and Homebrew on Linux). Homebrew installs formulae from a tap, a repository named
`homebrew-<something>`; with `joshua-hvmn/homebrew-tap` people install with:

```sh
brew install joshua-hvmn/tap/git-workflow
```

Setting the tap up once:

```sh
gh repo create joshua-hvmn/homebrew-tap --public --clone && cd homebrew-tap
mkdir Formula && cp ../git-workflow/packaging/homebrew/git-workflow.rb Formula/
git add Formula && git commit -m "git-workflow 2.0.0" && git push
brew install joshua-hvmn/tap/git-workflow && brew test git-workflow
brew audit --strict joshua-hvmn/tap/git-workflow
```

Each release: change the version in `url` and set `sha256` to the hash in the release's
`.tar.gz.sha256` asset, in both copies.
