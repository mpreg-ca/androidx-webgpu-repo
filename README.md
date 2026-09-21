# androidx-webgpu-repo

An unofficial Maven repository hosting a custom build of `androidx.webgpu:webgpu`.

**This is not an official Google/AndroidX release.** It is built from the
AndroidX `webgpu` module source with the Dawn native dependency pinned to a
different commit than the official release:

- Dawn source commit: `f92edf25efce9113ef66b777e47f8e8f8cca61af`
- Artifact versions:
  - `1.0.0-alpha06` — same version string as the official release; only
    resolves correctly if the consuming project excludes `androidx.webgpu`
    from `google()`/`mavenCentral()` (see note below).
  - `1.0.0-dev06` — a version Google's official `androidx.webgpu` release
    will never publish (it only ships `alpha` versions), so it can't collide
    with the real artifact.

Older builds (`1.0.0-alpha05` / `1.0.0-dev05`, Dawn commit
`b0713abb7699b219ff3f82f7caccc299047f95c0`) remain published in this repo for
consumers pinned to them.

See [`build-scripts/`](build-scripts/) for how these are built and how to
rebuild against a newer Dawn commit.

## Usage

Add this repository to your Gradle build:

```kotlin
repositories {
    maven { url = uri("https://raw.githubusercontent.com/mpreg-ca/androidx-webgpu-repo/main") }
}

dependencies {
    implementation("androidx.webgpu:webgpu:1.0.0-dev06")
}
```

**Important:** Google publishes an official `androidx.webgpu:webgpu` on
`google()`/`dl.google.com`. If you use the `1.0.0-alpha06` version from this
repo, you must exclude `androidx.webgpu` from `google()`/`mavenCentral()` in
your repository declarations, or Gradle will silently resolve the official
artifact instead of this one:

```kotlin
google { content { excludeGroup("androidx.webgpu") } }
mavenCentral { content { excludeGroup("androidx.webgpu") } }
```

Using the `1.0.0-dev06` version avoids this problem entirely, since that
version string doesn't exist on Google's repo.
