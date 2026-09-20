#!/usr/bin/env bash
# Shared paths for the GlistEngine helper scripts. Source it, do not run it.
#
# Everything is overridable from the environment so the same scripts work in a
# sandbox container, in CI and on a workstation that already has a glist
# workspace.

GLIST_APP_DIR="${GLIST_APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# The app name comes from CMakeLists, not from the directory, because the
# directory is whatever the checkout was cloned into and the build output is
# named after APP_NAME. In a sandbox the checkout is mounted at /work, which
# would otherwise leave us looking for work.html.
GLIST_APP_NAME="${GLIST_APP_NAME:-$(sed -n 's/^[[:space:]]*set([[:space:]]*APP_NAME[[:space:]]\+\([A-Za-z0-9_.+-]\+\)[[:space:]]*).*/\1/p' \
	"$GLIST_APP_DIR/CMakeLists.txt" | head -1)}"
GLIST_APP_NAME="${GLIST_APP_NAME:-$(basename "$GLIST_APP_DIR")}"
GLIST_ROOT="${GLIST_ROOT:-$HOME/glist}"
GLIST_ENGINE_DIR="$GLIST_ROOT/GlistEngine"
GLIST_PLUGINS_DIR="$GLIST_ROOT/glistplugins"
GLIST_APPS_DIR="$GLIST_ROOT/myglistapps"
GLIST_APP_WORKSPACE_DIR="$GLIST_APPS_DIR/$GLIST_APP_NAME"
GLIST_EMSDK_DIR="${GLIST_EMSDK_DIR:-$GLIST_ROOT/emsdk}"
GLIST_ENGINE_REF="${GLIST_ENGINE_REF:-main}"
GLIST_PLUGIN_REF="${GLIST_PLUGIN_REF:-main}"
# The engine tracks its own main, so the toolchain follows suit rather than
# pinning to a version that will age out. Set this to pin a build.
GLIST_EMSDK_VERSION="${GLIST_EMSDK_VERSION:-latest}"

GLIST_BUILD_DIR="${GLIST_BUILD_DIR:-$GLIST_ROOT/build/$GLIST_APP_NAME}"
GLIST_DIST_DIR="${GLIST_DIST_DIR:-$GLIST_APP_DIR/dist}"

# apt needs root in a container and sudo on a CI runner.
if [[ "$(id -u)" == "0" ]]; then
	GLIST_SUDO=""
else
	GLIST_SUDO="sudo"
fi

glist_say() {
	echo "[glist] $*"
}

# Mirrors the checkout into the workspace as a directory of symlinks, one per
# top level entry.
#
# The app has to sit at $GLIST_ROOT/myglistapps/<app> because its CMakeLists
# reaches the engine and the plugins through ../.., and that has to be a real
# directory: CMake stats those relative paths, so with a symlinked app
# directory the kernel resolves .. against the checkout and the plugins are
# looked for next to the git repository. Linking the contents instead keeps the
# build reading the live files with no copy to go stale.
glist_mirror_app() {
	if [[ -L "$GLIST_APP_WORKSPACE_DIR" ]]; then
		rm "$GLIST_APP_WORKSPACE_DIR"
	fi
	mkdir -p "$GLIST_APP_WORKSPACE_DIR"
	find "$GLIST_APP_WORKSPACE_DIR" -maxdepth 1 -mindepth 1 -type l -delete
	local entry name
	for entry in "$GLIST_APP_DIR"/*; do
		name="$(basename "$entry")"
		# build output of a previous run, never an input
		if [[ "$name" == "dist" || "$name" == "build" ]]; then
			continue
		fi
		ln -sfn "$entry" "$GLIST_APP_WORKSPACE_DIR/$name"
	done
}

# Playwright wants node 20 or newer and distributions still ship 18, so prefer
# the node the emsdk already installed over whatever is on PATH. Prepending its
# directory also fixes the tools whose shebang is /usr/bin/env node.
glist_use_node() {
	local candidate major
	for candidate in "${GLIST_NODE:-}" "$(ls -d "$GLIST_EMSDK_DIR"/node/*/bin/node 2>/dev/null | tail -1)" "$(command -v node || true)"; do
		[[ -x "$candidate" ]] || continue
		major="$("$candidate" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
		if [[ "$major" -ge 20 ]]; then
			PATH="$(dirname "$candidate"):$PATH"
			export PATH
			return 0
		fi
	done
	echo "no node 20 or newer found, run tools/setup-glist.sh or set GLIST_NODE" >&2
	return 1
}

# Puts emcc, emcmake and friends on PATH.
glist_activate_emsdk() {
	[[ -f "$GLIST_EMSDK_DIR/emsdk_env.sh" ]] || {
		echo "emsdk is missing from $GLIST_EMSDK_DIR, run tools/setup-glist.sh" >&2
		return 1
	}
	# emsdk_env.sh is noisy and touches unset variables, so it gets its own
	# relaxed scope.
	set +u
	# shellcheck disable=SC1091
	source "$GLIST_EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
	set -u
}
