#!/usr/bin/env bash
# Provision everything a GlistEngine app needs to build for the web.
#
#   tools/setup-glist.sh
#
# Safe to rerun: every step checks what is already there. Nothing is installed
# into the checkout, so the only cost of starting over is download time.
#
# The layout below is not a preference, it is what the CMake files require: an
# app reaches its engine and plugins through ../../GlistEngine and
# ../../glistplugins, so the app has to sit inside the workspace. Its entries
# are symlinked in rather than copied, so the build always reads the live files.
#
#   $GLIST_ROOT/GlistEngine
#   $GLIST_ROOT/glistplugins/gipWebGL
#   $GLIST_ROOT/myglistapps/<app>  ->  symlinks into this checkout
#   $GLIST_ROOT/emsdk
#
# See tools/glist-env.sh for the variables that change any of it.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/glist-env.sh"

PACKAGES=(git curl ca-certificates unzip xz-utils cmake ninja-build python3)

install_packages() {
	command -v apt-get >/dev/null || {
		glist_say "no apt-get, assuming the toolchain packages are present"
		return 0
	}
	local missing=()
	for pkg in "${PACKAGES[@]}"; do
		dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		glist_say "packages already installed"
		return 0
	fi
	glist_say "installing ${missing[*]}"
	$GLIST_SUDO apt-get update -qq
	DEBIAN_FRONTEND=noninteractive $GLIST_SUDO apt-get install -y -qq --no-install-recommends "${missing[@]}"
}

clone_or_keep() {
	local url="$1" dir="$2" ref="$3" recursive="$4"
	if [[ -d "$dir/.git" ]]; then
		glist_say "$(basename "$dir") already cloned ($(git -C "$dir" rev-parse --short HEAD))"
		return 0
	fi
	glist_say "cloning $url at $ref"
	local args=(--depth 1 --branch "$ref")
	[[ "$recursive" == "recursive" ]] && args+=(--recurse-submodules --shallow-submodules)
	git clone "${args[@]}" "$url" "$dir"
}

install_emsdk() {
	if [[ ! -d "$GLIST_EMSDK_DIR/.git" ]]; then
		glist_say "cloning emsdk"
		git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$GLIST_EMSDK_DIR"
	fi
	if [[ -f "$GLIST_EMSDK_DIR/.glist-installed" ]] &&
		[[ "$(cat "$GLIST_EMSDK_DIR/.glist-installed")" == "$GLIST_EMSDK_VERSION" ]]; then
		glist_say "emsdk $GLIST_EMSDK_VERSION already installed"
		return 0
	fi
	glist_say "installing emsdk $GLIST_EMSDK_VERSION (this downloads about a gigabyte)"
	"$GLIST_EMSDK_DIR/emsdk" install "$GLIST_EMSDK_VERSION"
	"$GLIST_EMSDK_DIR/emsdk" activate "$GLIST_EMSDK_VERSION"
	echo "$GLIST_EMSDK_VERSION" > "$GLIST_EMSDK_DIR/.glist-installed"
}

install_packages
mkdir -p "$GLIST_ROOT" "$GLIST_PLUGINS_DIR"
clone_or_keep https://github.com/GlistEngine/GlistEngine.git "$GLIST_ENGINE_DIR" "$GLIST_ENGINE_REF" plain
clone_or_keep https://github.com/GlistPlugins/gipWebGL.git "$GLIST_PLUGINS_DIR/gipWebGL" "$GLIST_PLUGIN_REF" recursive
install_emsdk
glist_mirror_app
glist_say "mirrored $GLIST_APP_WORKSPACE_DIR -> $GLIST_APP_DIR"

glist_activate_emsdk
glist_say "ready: $(emcc --version | head -1)"
glist_say "engine: $(git -C "$GLIST_ENGINE_DIR" rev-parse --short HEAD) on $GLIST_ENGINE_REF"
glist_say "next:   tools/build-web.sh"
