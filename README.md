# Kindle apps

One [KPM](https://kindlemodding.org/jailbreaking/whats-next/installing-homebrew.html#kpm)
repository for all of predakanga's packages for jailbroken Kindles.

## Use

With Wi-Fi on, in kterm or over SSH on the Kindle, add the repository once:

```sh
kpm add-repo https://predakanga.github.io/kindle-apps/repo.json
kpm update
```

Then install a package with `kpm install <id>`. The packages, and their
IDs, are listed at <https://predakanga.github.io/kindle-apps/>. To upgrade,
run `kpm update` and the same `kpm install` again.

## How it works

Nothing is stored here but the list of packages. The packages stay as
assets of their own repositories' GitHub releases.

- [`packages.txt`](packages.txt) lists the app repositories.
- [`tools/build-index.sh`](tools/build-index.sh) reads each one's releases.
  Every published `vX.Y.Z` release with a `.kpkg` attached becomes an
  artifact. The package's name, author, description, dependencies and
  platforms come from the `manifest.json` inside the `.kpkg`, whose version
  must match the tag. KPM installs the first artifact, so they're listed
  newest first.
- [`.github/workflows/publish.yml`](.github/workflows/publish.yml) runs it
  and publishes `repo.json` and a page listing the packages on GitHub
  Pages. It runs when an app's release workflow sends a `release`
  dispatch, when `main` changes, or by hand (*Actions > Publish the index >
  Run workflow*). There's no schedule, because GitHub turns off scheduled
  workflows in quiet repositories.

The design is recorded in Kindle Series Enabler's
[ADR 0005](https://github.com/predakanga/kindle-series-enabler/blob/main/docs/decisions/0005-one-index-for-all-packages.md).

## Adding a package

1. Its release workflow attaches the `.kpkg` to a `vX.Y.Z` GitHub release,
   with `manifest.json` at the archive root and the same version.
2. Add the repository to `packages.txt`.
3. Give the app repository a `KINDLE_APPS_TOKEN` secret: a fine-grained
   personal access token with access to `predakanga/kindle-apps` only,
   and the **Contents: Read and write** permission (which the dispatch
   API needs). Renew it when it expires.
4. End its release workflow with the dispatch:

   ```yaml
   - name: Update the kindle-apps index
     env:
       GH_TOKEN: ${{ secrets.KINDLE_APPS_TOKEN }}
     run: |
       if [ -z "$GH_TOKEN" ]; then
         echo "::warning::KINDLE_APPS_TOKEN isn't set: run kindle-apps' Publish the index workflow by hand"
         exit 0
       fi
       gh api repos/predakanga/kindle-apps/dispatches -f event_type=release \
         -f "client_payload[repo]=$GITHUB_REPOSITORY" -f "client_payload[tag]=$GITHUB_REF_NAME"
   ```

To build the index locally (needs `gh`, `curl`, `jq` and `tar`):

```sh
tools/build-index.sh packages.txt pages/index.html https://predakanga.github.io/kindle-apps/repo.json site
```

## Licence

Copyright (C) 2026 predakanga. The scripts and page here are under the GNU
General Public License, version 3 or later (see [`LICENSE`](LICENSE)). Each
package has its own licence.
