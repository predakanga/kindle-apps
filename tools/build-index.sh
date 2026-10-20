#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds the KPM repository index and its web page from the releases of
# every repository in PACKAGES.txt. Each published vX.Y.Z release with a
# .kpkg attached becomes an artifact. The package's name, author,
# description, dependencies and platforms come from the manifest.json
# inside each .kpkg, so app repositories need nothing beyond their
# releases. Grew out of Kindle Wireless Sync's tools/kpm-index.sh.
#
# Usage: tools/build-index.sh PACKAGES.txt TEMPLATE.html INDEX_URL OUT_DIR
#   Writes OUT_DIR/repo.json and OUT_DIR/index.html. Needs gh (with
#   GH_TOKEN in CI), curl, jq and tar.
set -eu

packages=$1
template=$2
index_url=$3
out=$4

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
: > "$work/artifacts.jsonl"

# One line per repository, ignoring comments and blank lines.
sed -e 's/#.*//' -e 's/[[:space:]]//g' "$packages" | grep -v '^$' | while read -r repo; do
    echo "$repo" >&2
    # shellcheck disable=SC2016 # a jq program, not shell
    gh api --paginate "repos/$repo/releases" --jq '
        .[]
        | select((.draft | not) and (.prerelease | not))
        | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
        | . as $r
        | .assets[]
        | select(.name | endswith(".kpkg"))
        | [$r.tag_name, .browser_download_url]
        | @tsv' |
    while IFS="$(printf '\t')" read -r tag url; do
        echo "  $tag: $url" >&2
        curl -fsSL -o "$work/pkg.kpkg" "$url"
        if ! tar -xzOf "$work/pkg.kpkg" manifest.json > "$work/manifest.json" 2>/dev/null; then
            echo "error: $url has no manifest.json at its root" >&2
            exit 1
        fi
        jq -c --arg repo "$repo" --arg tag "$tag" --arg url "$url" '
            if ("v" + (.version | map(tostring) | join("."))) != $tag
            then error("\($url): manifest version \(.version) does not match \($tag)")
            else {repo: $repo, url: $url, manifest: .}
            end' "$work/manifest.json" >> "$work/artifacts.jsonl"
    done
done

# Packages by ID; each one's details come from its newest artifact, and
# KPM installs the first artifact, so they're listed newest first.
jq -s '
  group_by(.manifest.id)
  | map(sort_by(.manifest.version) | reverse)
  | {
      manifest_version: 1,
      id: "kindle-apps",
      name: "predakanga'"'"'s Kindle apps",
      description: "KPM packages by predakanga (https://github.com/predakanga/kindle-apps)",
      packages: (map({
        key: .[0].manifest.id,
        value: {
          name: .[0].manifest.name,
          author: .[0].manifest.author,
          description: .[0].manifest.description,
          artifacts: map({
            url,
            version: .manifest.version,
            dependencies: (.manifest.dependencies // []),
            supported_platforms: .manifest.supported_platforms
          })
        }
      }) | from_entries)
    }' "$work/artifacts.jsonl" > "$out/repo.json"

# The page: one section per package, newest version, and where it lives.
jq -rs '
  group_by(.manifest.id)
  | map(sort_by(.manifest.version) | reverse | .[0])
  | sort_by(.manifest.name)
  | map(
      "<section>\n<h2>\(.manifest.name | @html) <small>\(.manifest.version | map(tostring) | join(".") | @html)</small></h2>\n"
      + "<p>\(.manifest.description | @html)</p>\n"
      + "<pre><code>kpm install \(.manifest.id | @html)</code></pre>\n"
      + "<p><a href=\"https://github.com/\(.repo | @html)\">Source, releases and issues</a></p>\n</section>")
  | if length == 0 then "<p>No packages have been released yet.</p>" else join("\n") end
  ' "$work/artifacts.jsonl" > "$work/packages.html"

awk -v url="$index_url" -v list="$work/packages.html" '
    /@PACKAGES@/ { while ((getline line < list) > 0) print line; next }
    { gsub(/@INDEX_URL@/, url); print }
' "$template" > "$out/index.html"

jq -r '.packages | to_entries[] | "\(.key): \(.value.artifacts | length) release(s)"' "$out/repo.json" >&2
