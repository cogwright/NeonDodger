#!/usr/bin/env bash
# Build the app for the browser with Emscripten and stage it in dist/.
#
#   tools/build-web.sh          # incremental
#   tools/build-web.sh --clean  # throw the CMake cache away first
#
# Provisions the workspace on first run, so a bare container needs this command
# and nothing else. dist/ is a complete static site: index.html plus the wasm,
# the loader and the packed assets.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/glist-env.sh"

CLEAN=0
[[ "${1:-}" == "--clean" ]] && CLEAN=1

if [[ ! -d "$GLIST_ENGINE_DIR" || ! -d "$GLIST_EMSDK_DIR" ]]; then
	glist_say "workspace incomplete, running setup first"
	"$(dirname "${BASH_SOURCE[0]}")/setup-glist.sh"
fi

# Picks up files added since the last build.
glist_mirror_app

glist_activate_emsdk

[[ $CLEAN -eq 1 ]] && rm -rf "$GLIST_BUILD_DIR"
mkdir -p "$GLIST_BUILD_DIR"

# Emscripten packs a directory that exists at link time, so the assets are
# staged next to the build. gGetAssetsDir() resolves to /assets at run time
# because getcwd() is / in the browser.
if [[ -d "$GLIST_APP_DIR/assets" ]]; then
	rm -rf "$GLIST_BUILD_DIR/assets"
	cp -r "$GLIST_APP_DIR/assets" "$GLIST_BUILD_DIR/assets"
	PRELOAD="--preload-file $GLIST_BUILD_DIR/assets@/assets"
else
	PRELOAD=""
fi

# Everything links into the one wasm binary. Assimp defaults to a shared
# library, and a shared build leaves a side module the page then tries to fetch
# at run time: "404 libassimp.so.5.3.0" and a game that never starts.
#
# Assimp is the bulk of a cold build, a few hundred translation units, and this
# game loads no models at all. Keeping the two formats a Glist app is most
# likely to want and dropping the rest cuts the first build roughly in half.
# Set GLIST_ASSIMP_ALL=1 for the full importer set.
if [[ "${GLIST_ASSIMP_ALL:-0}" == "1" ]]; then
	ASSIMP_ARGS=()
else
	ASSIMP_ARGS=(
		-DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF
		-DASSIMP_BUILD_OBJ_IMPORTER=ON
		-DASSIMP_BUILD_GLTF_IMPORTER=ON
		-DASSIMP_NO_EXPORT=ON
	)
fi

# Configured through the workspace mirror, never through the checkout path, or
# TOP_DIR lands outside the workspace and neither the engine nor the plugins are
# found.
emcmake cmake \
	-S "$GLIST_APP_WORKSPACE_DIR" \
	-B "$GLIST_BUILD_DIR" \
	-G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_EXE_LINKER_FLAGS="$PRELOAD" \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DBUILD_SHARED_LIBS=OFF \
	-DASSIMP_BUILD_ZLIB=ON \
	-DASSIMP_BUILD_TESTS=OFF \
	-DASSIMP_INSTALL=OFF \
	-DASSIMP_WARNINGS_AS_ERRORS=OFF \
	-DFT_DISABLE_HARFBUZZ=ON \
	"${ASSIMP_ARGS[@]}"

cmake --build "$GLIST_BUILD_DIR" -- -j"$(nproc)"

rm -rf "$GLIST_DIST_DIR"
mkdir -p "$GLIST_DIST_DIR"
cp "$GLIST_BUILD_DIR/$GLIST_APP_NAME.html" "$GLIST_DIST_DIR/index.html"
for ext in js wasm data; do
	[[ -f "$GLIST_BUILD_DIR/$GLIST_APP_NAME.$ext" ]] &&
		cp "$GLIST_BUILD_DIR/$GLIST_APP_NAME.$ext" "$GLIST_DIST_DIR/"
done
# Keeps GitHub Pages from running the output through Jekyll.
touch "$GLIST_DIST_DIR/.nojekyll"

glist_say "dist:"
ls -lh "$GLIST_DIST_DIR" | tail -n +2
