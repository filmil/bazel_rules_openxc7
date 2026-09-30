#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds the release archive and prints release notes to stdout.
set -o errexit -o nounset -o pipefail

TAG="$1"
VERSION="${TAG#v}"
ARCHIVE="bazel_rules_openxc7-${TAG}.zip"

# Exclude repository clutter and build artifacts matching previous
# zip-release exclusions.
zip --quiet --symlinks --recurse-paths "${ARCHIVE}" . \
  -x '*.git*' '/*node_modules/*' '.editorconfig' '*bazel-*' \
     'release_notes.txt' "${ARCHIVE}"

cat <<EOF
## Using Bzlmod

\`\`\`starlark
bazel_dep(name = "rules_openxc7", version = "${VERSION}")
\`\`\`
EOF
