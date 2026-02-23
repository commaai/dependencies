# dependencies

a central repo for managing and [vendoring](https://htmx.org/essays/vendoring/) third party dependencies for all comma projects.

since all our projects are Python, we wrap each vendored dependency as a pip package. `git clone` and `uv sync` is all you need.

motivations for this approach
- `apt-get` is slow
- `apt-get` updates its packages on a schedule we don't control
- `apt-get` package versions don't match `brew` versions
- `apt-get` doesn't come with Arch Linux
- `apt-get` doesn't always have the exact package we need
- `apt-get` packages are often bloated

<!--
this critically adds friction to adding dependencies to our project
- `apt-get` installing a package is easy. is it 1MB, 10MB, or 100MB? no idea.
- `apt-get` installing a package is much easier than adding it here. how much do you want it?
-->

`uv`, as opposed to `apt-get`, `brew`, and friends, is fast and already used in our projects.

we target the following platforms:
- Linux x86_64
- Linux aarch64
- Darwin aarch64 (Apple Silicon)

contributions welcome for other platforms!

## packages

| package           | description                                                              |
|-------------------|--------------------------------------------------------------------------|
| gcc-arm-none-eabi | builds [panda](https://github.com/commaai/panda) firmware for STM32 MCUs |
| capnproto         | message serialization for openpilot                                      |
| ffmpeg            | video encode and decode for openpilot                                    |
| git-lfs           | for tracking large files in openpilot                                    |
| zeromq            | bridging the openpilot IPC between different hosts                       |

## usage

```python
dependencies = [
  "capnproto @ git+https://github.com/commaai/dependencies.git@releases#subdirectory=capnproto",
  "ffmpeg @ git+https://github.com/commaai/dependencies.git@releases#subdirectory=ffmpeg",
]
```

## workflow

to add a new package:
* start a new top-level directory as a new package
* `./test.sh` tests the building of all packages
*  on pushes to `master`, wheels are built for our target platforms and pushed to a GitHub release
*  the `releases` branch contains shim packages that allow pointing to a git branch and always getting the appropriate wheel for your platform
