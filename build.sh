#!/usr/bin/env bash
# Build an Appgate appliance customization zip that serves Quake III Arena
# (free demo content, plus the CPMA mod) to web browsers, using QuakeJS.
#
#   ./build.sh --accept-eula [--out quake3.zip]
#
# Needs: git, npm, python3, zip (Linux or WSL with internet access).
# --accept-eula means you accept the Quake III Arena demo license
# (written into the package as data/Q3DEMO-EULA.txt).
set -euo pipefail

# Pinned sources: an upstream change must not change the package silently.
QUAKEJS_REPO=https://github.com/nerosketch/quakejs.git
QUAKEJS_REF=00230a844d64ac6158af8f129411ddd4e621e3a2
DOCKER_REPO=https://github.com/treyyoder/quakejs-docker.git
DOCKER_REF=fa26e7e5205c1e7375765bb4540464d7c381e313
NODE_PKG=node-linux-x64@22.23.4      # official Node.js binary, via npm
WS_PKG=ws@0.4.32                      # the server uses ws 0.4's upgradeReq API

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
OUT="$HERE/appgate-quake3.zip"
EULA=false
LIMIT=$((200 * 1024 * 1024))

while [ $# -gt 0 ]; do
    case "$1" in
        --accept-eula) EULA=true ;;
        --out) OUT="$(realpath -m "$2")"; shift ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ "$EULA" = true ] || { echo "Pass --accept-eula to accept the Quake III Arena demo license" >&2; exit 1; }
for t in git npm python3 zip tar; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"
D="$PKG/data"
mkdir -p "$D/server" "$D/html" "$D/html/assets/baseq3"

absent() {  # pattern file: fail if pattern is present
    if grep -q "$1" "$2"; then echo "patch check failed: '$1' still in $2" >&2; exit 1; fi
}
fetch() {  # repo ref dir
    git init -q "$3"
    git -C "$3" fetch -q --depth 1 "$1" "$2"
    git -C "$3" checkout -q FETCH_HEAD
}
echo "==> Fetching QuakeJS sources (pinned)"
fetch "$QUAKEJS_REPO" "$QUAKEJS_REF" "$WORK/quakejs"
fetch "$DOCKER_REPO" "$DOCKER_REF" "$WORK/qdocker"

echo "==> Node.js runtime ($NODE_PKG) and $WS_PKG"
(cd "$WORK" && npm pack -q "$NODE_PKG" >/dev/null && tar -xzf node-linux-x64-*.tgz)
install -m 0755 "$WORK/package/bin/node" "$D/node"
(cd "$D/server" && npm install -q --no-save --no-package-lock --ignore-scripts \
    --no-audit --no-fund --omit=dev "$WS_PKG" >/dev/null)

echo "==> Game server"
cp "$WORK/qdocker/include/ioq3ded/ioq3ded.fixed.js" "$D/server/ioq3ded.js"
# Same heap raise as quakejs-docker, so the 128MB+ hunk fits.
sed -i "s/|| 234881024/|| 536870912/" "$D/server/ioq3ded.js"
grep -q "|| 536870912" "$D/server/ioq3ded.js"
grep -q "realClientAddress" "$D/server/ioq3ded.js"

echo "==> Browser client"
cp "$WORK/quakejs/html/ioquake3.js" "$WORK/quakejs/html/game.css" "$D/html/"
cp "$WORK/quakejs/html/"favicon* "$D/html/" 2>/dev/null || true
cp "$WORK/quakejs/html/index.html" "$D/html/index.html"
J="$D/html/ioquake3.js"
# Asset URLs relative to the page's own origin, wss:// when served over https.
sed -i "s|'http://' + root|'//' + root|g; s|'http://' + fs_cdn|'//' + fs_cdn|g" "$J"
sed -i "s|'ws://' + addr|((typeof location !== 'undefined' \&\& location.protocol === 'https:') ? 'wss://' : 'ws://') + addr|g" "$J"
sed -i "s|return Pointer_stringify(_Com_GetCDN());|return window.location.host;|" "$J"
sed -i "s|var url = '//' + fs_cdn + '/assets/manifest.json';|var url = '//' + window.location.host + '/assets/manifest.json';|" "$J"
grep -q "wss://" "$J"
absent "_Com_GetCDN());" "$J"
absent "'//' + fs_cdn" "$J"
# Supplied-pak and large-truncate fixes, applied to server and client alike.
python3 "$WORK/qdocker/tools/patch-quakejs.py" "$D/server/ioq3ded.js" "$J"
"$D/node" --check "$D/server/ioq3ded.js"

P="$D/html/index.html"
# Page and game both come from whatever host:port the browser used.
HOSTPORT="window.location.hostname + ':' + (window.location.port || (window.location.protocol === 'https:' ? '443' : '80'))"
sed -i "s/'quakejs:80'/window.location.host/g; s/'quakejs:27960'/$HOSTPORT/g" "$P"
sed -i "s/\['+set', 'fs_cdn', window.location.host/['+set', 'com_hunkMegs', '256', '+set', 'fs_cdn', window.location.host/" "$P"
sed -i 's#<script type="text/javascript" src="ioquake3.js">#<script>var Module={TOTAL_MEMORY:536870912};</script><script type="text/javascript" src="ioquake3.js">#' "$P"
sed -i 's#form.submit();#alert("Quake 3 stopped: " + err); window.location.href = "/"; return;#' "$P"
sed -i 's#<title>[^<]*</title>#<title>Quake 3 Arena</title>#' "$P"
# Join screen: per-browser name and settings, passed as +set before +connect.
cp "$SRC/data/join.js" "$SRC/data/join.css" "$D/html/"
sed -i 's#window.onload = function () {#window.q3launch = function (playerArgs) {#' "$P"
sed -i "/^\s*var args = \['+set', 'com_hunkMegs'/a\\var ci = args.indexOf('+connect'); if (playerArgs \&\& ci >= 0) { args.splice.apply(args, [ci, 0].concat(playerArgs)); }" "$P"
sed -i 's#</head>#\t\t<link rel="stylesheet" href="join.css"><script src="join.js" defer></script>\n\t</head>#' "$P"
grep -q "window.q3launch = function (playerArgs)" "$P"
grep -q "args.splice.apply(args, \[ci, 0\].concat(playerArgs))" "$P"
grep -q 'src="join.js"' "$P"
grep -q "^var ci = args.indexOf('+connect')" "$P"
absent "window.onload" "$P"
grep -q "com_hunkMegs" "$P"
grep -q "TOTAL_MEMORY:536870912" "$P"
absent "quakejs:" "$P"

echo "==> Demo content"
A="$WORK/qdocker/include/assets"
cp "$A"/*-linuxq3ademo-*.sh "$A"/*-linuxq3apoint-*.run "$D/html/assets/"
cp "$A"/baseq3/*.pk3 "$D/html/assets/baseq3/"
mkdir -p "$D/html/assets/cpma"
cp "$A"/cpma/*.pk3 "$D/html/assets/cpma/"     # Challenge ProMode Arena mod + maps
cp "$A/manifest.json" "$D/html/assets/manifest.json"
# The demo license must accompany every copy.
python3 - "$D/server/ioq3ded.js" "$D/Q3DEMO-EULA.txt" <<'PY'
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'eula:("(?:[^"\\]|\\.)*")', src)
open(sys.argv[2], "w").write(json.loads(m.group(1)) + "\n")
PY
grep -q "LIMITED USE SOFTWARE LICENSE AGREEMENT" "$D/Q3DEMO-EULA.txt"

echo "==> Assembling package"
cp "$SRC/start" "$SRC/stop" "$SRC/status" "$SRC/metadata.txt" "$PKG/"
cp "$SRC/data/quake3.conf" "$SRC/data/server.cfg" "$SRC/data/server-cpma.cfg" "$SRC/data/web.js" "$D/"
printf 'Accepted at build time %s\n' "$(date -u +%FT%TZ)" > "$D/EULA-ACCEPTED"
sed -i 's/\r$//' "$PKG/start" "$PKG/stop" "$PKG/status" "$PKG/metadata.txt" \
    "$D/quake3.conf" "$D/server.cfg" "$D/server-cpma.cfg" "$D/web.js"
chmod 0755 "$PKG/start" "$PKG/stop" "$PKG/status" "$D/node"

rm -f "$OUT"
(cd "$PKG" && zip -X -r -q "$OUT" start stop status metadata.txt data)
SIZE=$(stat -c %s "$OUT")
echo "==> Built $OUT ($((SIZE / 1024 / 1024)) MB)"
if [ "$SIZE" -gt "$LIMIT" ]; then
    echo "WARNING: exceeds Appgate's 200 MB customization limit" >&2
    exit 1
fi
