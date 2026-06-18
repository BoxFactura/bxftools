#!/usr/bin/env bash
#
# Rebuilds the bundled unar payload from Ubuntu 24.04 (requires Docker).
#
# Produces a single consolidated archive named like bxfzip's binaries:
#   bin/bxfunar-ubuntu-24.04_amd64.tar.gz
#
# It carries the `unar` binary plus only the GNUstep Objective-C runtime it
# needs (libgnustep-base, libobjc) -- the libraries a stock host never has.
# Everything else unar links (libicu74, libxml2, libxslt, libdbus, libavahi) is
# resolved from the host at runtime and is deliberately NOT bundled, keeping the
# payload lean. This works because we pin to 24.04, whose native libs match.
#
set -euo pipefail

cd "$(dirname "$0")/.."
SUFFIX="ubuntu-24.04_amd64"
ARCHIVE="bxfunar-${SUFFIX}.tar.gz"

# Regenerate from scratch: drop any prior archive and expanded payload dir.
rm -f "bin/${ARCHIVE}"
rm -rf "bin/bxfunar-${SUFFIX}"

docker run --rm -v "$PWD/bin:/out" ubuntu:24.04 bash -euc '
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unar >/dev/null

  work=$(mktemp -d)
  # unar (executable) plus only the GNUstep libs it requests, each named after
  # the soname the binary looks up (the left side of `ldd`).
  install -m755 -T /usr/bin/unar "$work/unar"
  ldd /usr/bin/unar | awk "/libgnustep-base|libobjc/ {print \$1, \$3}" | while read -r soname path; do
    install -m644 -T "$path" "$work/$soname"
  done

  ( cd "$work" && tar -czf "/out/'"${ARCHIVE}"'" unar lib* )
  chown '"$(id -u):$(id -g)"' "/out/'"${ARCHIVE}"'"
'

echo "Wrote consolidated unar payload:"
ls -la "bin/${ARCHIVE}"
