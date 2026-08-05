test
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

pre-built wheels are published to PyPI under the `comma-deps-` prefix. the import name
is unchanged (e.g. `import capnproto`), only the distribution name is prefixed.
packages require Python 3.12 or newer.

```python
dependencies = [
  "comma-deps-capnproto>=1.0.1,<1.0.2",
  "comma-deps-ffmpeg>=7.1.0,<7.1.1",
]
```

to build from source instead, point at the master branch of this repo:

```python
dependencies = [
  "comma-deps-capnproto @ git+https://github.com/commaai/dependencies.git@master#subdirectory=capnproto",
  "comma-deps-ffmpeg @ git+https://github.com/commaai/dependencies.git@master#subdirectory=ffmpeg",
]
```

## workflow

to add a new package:
* start a new top-level directory as a new package
* `./build.sh` builds all packages, `./test_wheels_in_image.sh` tests the built wheels in a range of distros
*  on pushes to `master`, wheels are built for our target platforms, tested, and published to PyPI

> [!NOTE]
> PyPI does not allow overwriting an uploaded file, so every master commit publishes
> fresh versions as `<package version>.postN`, where `N` is `git rev-list --count HEAD`
> for the commit being built (a commit hash isn't a valid PyPI version). package
> `pyproject.toml` files keep the clean upstream version; `./build.sh` applies the
> `.postN` suffix only while building wheels.
