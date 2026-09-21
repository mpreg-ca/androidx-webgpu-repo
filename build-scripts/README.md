# Build workspace layout

This repo only stores the final Maven artifacts. The actual build happens in a
persistent workspace under `/home/w` (NOT in scratch/tmp, so it survives
across sessions and can be reused for the next Dawn bump):

| Path                                  | What it is                                                          |
|----------------------------------------|----------------------------------------------------------------------|
| `~/androidx-main-build/`               | `repo`-synced checkout of the `androidx-main` manifest (AOSP). The webgpu module lives at `frameworks/support/webgpu/webgpu`. The prebuilt Dawn `.so` files it links against live at `prebuilts/androidx/webgpu/jni/<abi>/libwebgpu_c_bundled.so`. |
| `~/dawn-build/dawn/`                   | Plain git checkout of `https://dawn.googlesource.com/dawn`, plus a `.gclient` file so `gclient sync` pulls all `third_party/` deps. |
| `~/depot_tools/`                       | Chromium's `depot_tools` (provides `gclient`), needed to sync Dawn's third-party deps. |
| `~/gradle-dist/gradle-8.10.1/`         | Standalone Gradle 8.10.1 (Dawn's `tools/android` build doesn't ship a gradle wrapper jar/script, so we use this directly). |
| `~/.jabba/jdk/openjdk@17.0.2/`         | JDK 17, used for building Dawn's Android AAR (androidx-main brings its own JDK 21 for its own build). |
| `~/android-sdk/ndk/27.0.12077973/`     | NDK version matching Dawn's `tools/android/webgpu/build.gradle` default `ndkVersion`. |

Run `update-dawn.sh <dawn-commit-sha>` (in this directory) to do a full
refresh end to end. It's idempotent — re-running with the same commit is fast
because `gclient sync` and the androidx `repo sync` are incremental.

## What the script does

1. `git fetch` + `checkout` the given commit in `~/dawn-build/dawn`.
2. `gclient sync -D` to update `third_party/` deps to match that commit's `DEPS`.
3. Build `libwebgpu_c_bundled.so` for all 4 ABIs via
   `~/dawn-build/dawn/tools/android` (CMake + NDK, driven by Gradle).
4. Copy the resulting `.so` files into
   `~/androidx-main-build/prebuilts/androidx/webgpu/jni/<abi>/`.
5. Update `frameworks/support/webgpu/webgpu/meta/dawn_build_metadata.json`
   with the new commit sha.
6. `repo sync` the androidx-main checkout (picks up upstream webgpu source
   changes too, not just our local edits) then run
   `ANDROIDX_PROJECTS=MAIN ./gradlew :webgpu:webgpu:assembleRelease`, which
   also produces the full local Maven repo (pom/module/checksums) as a
   byproduct under `~/androidx-main-build/out/dist/repository` (exact path
   printed by the script).
7. Copy the new version directories into this repo's
   `androidx/webgpu/webgpu/`, regenerate `maven-metadata.xml` (+ checksums),
   and update the root `README.md` with the new Dawn commit and version.
8. `git add` + `git commit` in this repo (does not push).

## Size

The upstream Dawn `tools/android/webgpu/build.gradle` compiles the native lib
with `-O2` (RelWithDebInfo default). `update-dawn.sh` patches this to `-Os`
after each `git checkout`, since that file is reset to upstream on every
Dawn commit switch. Measured effect (Dawn commit `f92edf25e...`): 5-16%
smaller `.so` per ABI (biggest win on x86/x86_64), no functional change.

Other options investigated and rejected:
- `DAWN_ENABLE_NULL=OFF` / `TINT_BUILD_NULL_WRITER=OFF`: breaks the build —
  Dawn's OpenGL(ES) backend has a hard source dependency on Tint's null
  writer (`no member named 'null' in namespace 'tint'` if disabled).
- `TINT_ENABLE_IR_VALIDATION_ASSERTS=OFF` / `TINT_ENABLE_IR_DUMPING=OFF`:
  negligible (~0.16%) — not worth the extra CMake args.
- Disabling `DAWN_ENABLE_OPENGLES` (and the GLSL writer/validator that comes
  with it) would likely be the single biggest remaining lever, but it's a
  real functionality tradeoff (no fallback on devices without Vulkan), not
  a free win — not applied here.

The remaining size gap vs. the official Google-published artifact
(`dl.google.com`, built from a much older Dawn commit) is mostly just
upstream Dawn code growth over time, not a build config difference — both
builds use the same CMake args baked into `build.gradle`.

## Notes / gotchas

- The androidx-main webgpu module version currently comes from
  `frameworks/support/libraryversions.toml` (`WEBGPU = "1.0.0-alphaNN"`)
  upstream — it may already be bumped by the time you sync, so don't assume
  the last version you built is still current.
- Dawn's own `tools/android` gradle project has no committed
  `gradle-wrapper.jar`/`gradlew`; the script copies androidx-main's wrapper
  jar (any version works, it's just the bootstrap) or you can use the
  standalone Gradle 8.10.1 install directly, which the script does.
- `~/androidx-main-build/prebuilts/androidx/webgpu` is itself a separate git
  repo (`platform/prebuilts/androidx/webgpu`) — we only edit the working
  tree locally, we never commit/push there.
