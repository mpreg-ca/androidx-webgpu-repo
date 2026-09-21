#!/usr/bin/env bash
# Rebuild androidx.webgpu:webgpu against a new Dawn commit and refresh this
# repo's Maven layout. See build-scripts/README.md for the workspace layout
# this script assumes.
#
# Usage: build-scripts/update-dawn.sh <dawn-commit-sha>
set -euo pipefail

DAWN_COMMIT="${1:?usage: update-dawn.sh <dawn-commit-sha>}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROIDX_ROOT="$HOME/androidx-main-build"
SUPPORT_DIR="$ANDROIDX_ROOT/frameworks/support"
DAWN_DIR="$HOME/dawn-build/dawn"
DEPOT_TOOLS="$HOME/depot_tools"
GRADLE_BIN="$HOME/gradle-dist/gradle-8.10.1/bin/gradle"
JAVA_HOME_17="$HOME/.jabba/jdk/openjdk@17.0.2"
ANDROID_SDK="$HOME/android-sdk"
TOML="$SUPPORT_DIR/libraryversions.toml"
META_JSON="$SUPPORT_DIR/webgpu/webgpu/meta/dawn_build_metadata.json"

log() { echo "== $* =="; }

# ---------------------------------------------------------------------------
# 1. Dawn: fetch the target commit and sync third_party/ deps to match.
# ---------------------------------------------------------------------------
log "Fetching Dawn commit $DAWN_COMMIT"
git -C "$DAWN_DIR" fetch origin "$DAWN_COMMIT"
git -C "$DAWN_DIR" checkout FETCH_HEAD

log "gclient sync (Dawn third_party deps)"
(cd "$DAWN_DIR" && PATH="$DEPOT_TOOLS:$PATH" gclient sync -D --no-history -j16)

# ---------------------------------------------------------------------------
# 1b. Patch the release C++ flags to optimize for size (-Os instead of the
#     default -O2). This is a real, measured win (~5-16% smaller .so per
#     ABI) with no functional change. It has to be re-applied every time
#     because `git checkout` on $DAWN_DIR resets this file to upstream.
# ---------------------------------------------------------------------------
BUILD_GRADLE="$DAWN_DIR/tools/android/webgpu/build.gradle"
if ! grep -q "CMAKE_CXX_FLAGS_RELWITHDEBINFO" "$BUILD_GRADLE"; then
  sed -i "s|arguments '-DANDROID_STL=c++_shared', '-DDAWN_BUILD_PROTOBUF=OFF'|arguments '-DANDROID_STL=c++_shared', '-DDAWN_BUILD_PROTOBUF=OFF', '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-Os -DNDEBUG'|" "$BUILD_GRADLE"
fi

# ---------------------------------------------------------------------------
# 2. Build libwebgpu_c_bundled.so for all 4 ABIs.
# ---------------------------------------------------------------------------
log "Building Dawn Android native libs (all ABIs)"
export JAVA_HOME="$JAVA_HOME_17"
export PATH="$JAVA_HOME/bin:$DEPOT_TOOLS:$PATH"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"

DAWN_ANDROID_DIR="$DAWN_DIR/tools/android"
echo "sdk.dir=$ANDROID_SDK" > "$DAWN_ANDROID_DIR/local.properties"

"$GRADLE_BIN" -p "$DAWN_ANDROID_DIR" :webgpu:assembleRelease \
  -PdawnBuildType=Release -PnativeTargets=webgpu_c_bundled --no-daemon

SO_SRC_DIR="$DAWN_ANDROID_DIR/webgpu/build/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib"

# ---------------------------------------------------------------------------
# 3. Copy the built .so files into androidx-main's prebuilts tree.
# ---------------------------------------------------------------------------
log "Copying built .so files into androidx-main prebuilts"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  src="$SO_SRC_DIR/$abi/libwebgpu_c_bundled.so"
  [[ -f "$src" ]] || { echo "ERROR: missing $src" >&2; exit 1; }
  cp -v "$src" "$ANDROIDX_ROOT/prebuilts/androidx/webgpu/jni/$abi/libwebgpu_c_bundled.so"
done

# ---------------------------------------------------------------------------
# 4. Record the new Dawn commit in the webgpu module's build metadata.
# ---------------------------------------------------------------------------
log "Updating $META_JSON"
printf '{ "dawn_source_commit_sha": "%s" }\n' "$DAWN_COMMIT" > "$META_JSON"

# ---------------------------------------------------------------------------
# 5. Sync androidx-main and build the "alpha" release version.
# ---------------------------------------------------------------------------
log "repo sync androidx-main"
(cd "$ANDROIDX_ROOT" && python3 ./repo sync -c -j16 --no-tags)

alpha_version=$(grep -m1 -E '^WEBGPU = "[^"]+"$' "$TOML" | sed -E 's/.*"([^"]+)".*/\1/')
log "Current upstream WEBGPU version: $alpha_version"
dev_version="${alpha_version/alpha/dev}"
if [[ "$dev_version" == "$alpha_version" ]]; then
  echo "ERROR: expected an 'alphaNN' version, got '$alpha_version'; edit this script's dev-version derivation." >&2
  exit 1
fi

build_and_publish() {
  local version="$1"
  local tmp
  tmp=$(mktemp)
  sed -E "s/^WEBGPU = \"[^\"]+\"\$/WEBGPU = \"$version\"/" "$TOML" > "$tmp" && mv "$tmp" "$TOML"
  (
    cd "$SUPPORT_DIR"
    export ANDROIDX_PROJECTS=MAIN
    ./gradlew :webgpu:webgpu:publishAllPublicationsToMaven2Repository --rerun
  )
  local src_dir="$ANDROIDX_ROOT/out/androidx/webgpu/webgpu/build/repository/androidx/webgpu/webgpu/$version"
  [[ -d "$src_dir" ]] || { echo "ERROR: expected output dir missing: $src_dir" >&2; exit 1; }
  local dest_dir="$REPO_DIR/androidx/webgpu/webgpu/$version"
  mkdir -p "$dest_dir"
  cp -v "$src_dir"/* "$dest_dir/"
}

log "Building + publishing $alpha_version"
build_and_publish "$alpha_version"

log "Building + publishing $dev_version"
build_and_publish "$dev_version"

# Restore the real (alpha) version so the upstream-synced tree stays clean.
sed -E "s/^WEBGPU = \"[^\"]+\"\$/WEBGPU = \"$alpha_version\"/" "$TOML" > "$TOML.tmp" && mv "$TOML.tmp" "$TOML"

# ---------------------------------------------------------------------------
# 6. Regenerate maven-metadata.xml with all known versions.
# ---------------------------------------------------------------------------
log "Regenerating maven-metadata.xml"
METADATA_DIR="$REPO_DIR/androidx/webgpu/webgpu"
mapfile -t versions < <(find "$METADATA_DIR" -maxdepth 1 -type d -name '1.0.0-*' -printf '%f\n' | sort -V)
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<metadata>'
  echo '  <groupId>androidx.webgpu</groupId>'
  echo '  <artifactId>webgpu</artifactId>'
  echo '  <versioning>'
  echo "    <latest>$dev_version</latest>"
  echo "    <release>$dev_version</release>"
  echo '    <versions>'
  for v in "${versions[@]}"; do echo "      <version>$v</version>"; done
  echo '    </versions>'
  echo "    <lastUpdated>$(date -u +%Y%m%d%H%M%S)</lastUpdated>"
  echo '  </versioning>'
  echo '</metadata>'
} > "$METADATA_DIR/maven-metadata.xml"
for algo in md5 sha1 sha256 sha512; do
  "${algo}sum" "$METADATA_DIR/maven-metadata.xml" | cut -d' ' -f1 > "$METADATA_DIR/maven-metadata.xml.$algo"
done

log "Done."
echo "New versions: $alpha_version, $dev_version"
echo "Now: update README.md's Dawn commit + version references, then"
echo "  git -C '$REPO_DIR' add -A && git -C '$REPO_DIR' commit"
