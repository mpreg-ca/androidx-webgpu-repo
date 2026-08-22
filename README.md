# androidx-webgpu-repo

An unofficial Maven repository hosting a custom build of `androidx.webgpu:webgpu`.

**This is not an official Google/AndroidX release.** It is built from the
AndroidX `webgpu` module source with the Dawn native dependency pinned to a
different commit than the official release:

- Dawn source commit: `b0713abb7699b219ff3f82f7caccc299047f95c0`
- Artifact version: `1.0.0-alpha05`

## Usage

Add this repository to your Gradle build:

```kotlin
repositories {
    maven { url = uri("https://raw.githubusercontent.com/mpreg-ca/androidx-webgpu-repo/main") }
}

dependencies {
    implementation("androidx.webgpu:webgpu:1.0.0-alpha05")
}
```
