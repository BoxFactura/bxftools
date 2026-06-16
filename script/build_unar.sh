#!/usr/bin/env bash
#
# Rebuilds bin/unar/*.gz from Ubuntu 24.04 (requires Docker).
#
# Ships the `unar` binary plus only the GNUstep Objective-C runtime it needs
# (libgnustep-base, libobjc) -- the libraries a stock host never has. Everything
# else unar links (libicu74, libxml2, libxslt, libdbus, libavahi) is resolved
# from the host at runtime and is deliberately NOT bundled, keeping the payload
# lean. This works because we pin to 24.04, whose native lib versions match.
#
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="bin/unar"

# Regenerate from scratch so stale files never get re-compressed into *.gz.gz.
rm -rf "$OUT"
mkdir -p "$OUT"

docker run --rm -v "$PWD/$OUT:/out" ubuntu:24.04 bash -euc '
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unar >/dev/null

  # Copy unar plus only the GNUstep libs it requests, naming each file after
  # the soname the binary actually looks up (the left side of `ldd`).
  install -m755 -T /usr/bin/unar /out/unar
  ldd /usr/bin/unar | awk "/libgnustep-base|libobjc/ {print \$1, \$3}" | while read -r soname path; do
    install -m644 -T "$path" "/out/$soname"
  done

  chown -R '"$(id -u):$(id -g)"' /out
'

# Compress every freshly-installed file; the dir contains only these three.
gzip -9 "$OUT"/*

echo "Wrote lean unar payload:"
ls -la "$OUT"/*.gz
du -sh "$OUT"
