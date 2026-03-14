# dependencies

a central repo for [vendoring](https://htmx.org/essays/vendoring/) all third party dependencies for comma projects.

since all our projects are Python, we wrap each vendored dependency as a pip package. `git clone` and `uv sync` is all you need.

motivations for this approach
- `apt-get` is slow
- `apt-get` updates its packages on a schedule we don't control
- `apt-get` package versions don't match `brew` versions
- `apt-get` doesn't come with Arch Linux
- `apt-get` packages come with more than we need, bloating our project footprint 

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

<!--
## packages

| package           | description                                                              |
|-------------------|--------------------------------------------------------------------------|
| gcc-arm-none-eabi | builds [panda](https://github.com/commaai/panda) firmware for STM32 MCUs |
| capnproto         | message serialization for openpilot                                      |
| ffmpeg            | video encode and decode for openpilot                                    |
| git-lfs           | for tracking large files in openpilot                                    |
| zeromq            | bridging the openpilot IPC between different hosts                       |
-->

## usage

```python
dependencies = [
  # use per-package release branches for pre-built wheels
  "capnproto @ git+https://github.com/commaai/dependencies.git@release-capnproto#subdirectory=capnproto",
  "ffmpeg @ git+https://github.com/commaai/dependencies.git@release-ffmpeg#subdirectory=ffmpeg",

  # use the master branch to build the package on pip install
  "capnproto @ git+https://github.com/commaai/dependencies.git@master#subdirectory=capnproto",
  "ffmpeg @ git+https://github.com/commaai/dependencies.git@master#subdirectory=ffmpeg",
]
```

## workflow

to add a new package:
* start a new top-level directory as a new package
* `./test.sh` tests the building of all packages
*  on pushes to `master`, wheels are built for our target platforms and pushed to a GitHub release
*  each `release-<package>` branch contains a single shim package, so old lockfiles keep resolving even as new packages are added
