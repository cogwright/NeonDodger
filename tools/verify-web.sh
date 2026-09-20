#!/usr/bin/env bash
# Run the browser checks against dist/.
#
#   tools/build-web.sh && tools/verify-web.sh
#
# Playwright and its Chromium live in the glist workspace, not in the checkout,
# so this leaves no node_modules behind. Screenshots land in artifacts/.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/glist-env.sh"

NODE_ROOT="$GLIST_ROOT/node"
export PLAYWRIGHT_BROWSERS_PATH="$GLIST_ROOT/playwright-browsers"

glist_use_node

[[ -f "$GLIST_DIST_DIR/index.html" ]] || {
	echo "no build in $GLIST_DIST_DIR, run tools/build-web.sh first" >&2
	exit 1
}

if [[ ! -d "$NODE_ROOT/node_modules/playwright" ]]; then
	glist_say "installing playwright into $NODE_ROOT"
	mkdir -p "$NODE_ROOT"
	npm install --silent --prefix "$NODE_ROOT" playwright
fi

if [[ ! -d "$PLAYWRIGHT_BROWSERS_PATH" ]]; then
	glist_say "downloading chromium (about 150 MB, once per container)"
	"$NODE_ROOT/node_modules/.bin/playwright" install --with-deps chromium
fi

export PLAYWRIGHT_MODULE="$NODE_ROOT/node_modules/playwright/index.js"
export DIST_DIR="$GLIST_DIST_DIR"
export ARTIFACTS_DIR="${ARTIFACTS_DIR:-$GLIST_APP_DIR/artifacts}"

cd "$GLIST_APP_DIR"
exec node tools/verify-web.mjs
