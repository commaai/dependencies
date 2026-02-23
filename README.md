# dependencies

a central repo for managing and [vendoring](https://htmx.org/essays/vendoring/) third party dependencies for all comma projects.

all of our projects are python projects, so each of these gets packaged as a pip project.

motivations for this approach
- `apt-get` is slow
- `apt-get` updates its packages on a schedule we don't control
- `apt-get` pacakge versions don't match `brew` versions
- `apt-get` doesn't comw with Arch Linux
- `apt-get` doesn't always have the exact package we need
- `apt-get` packages are often larger than we need

this critically adds friction to adding dependencies to our project
- `apt-get` installing a package is easy. is it 1MB, 10MB, or 100MB? no idea.
- `apt-get` installing a package is much easier than adding it here. how much do you want it?

`uv`, as opposed to `apt-get`, `brew`, and friends, is fast and already used in our projects since we use Python.

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

## usage

add it to a project like this:
```python
dependences = [
  "capnproto @ git+https://github.com/commaai/dependencies.git@more-vendor#subdirectory=capnproto",
  "ffmpeg @ git+https://github.com/commaai/dependencies.git@more-vendor#subdirectory=ffmpeg",
]
```
