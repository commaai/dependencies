# dependencies

a central repo for managing and [vendoring](https://htmx.org/essays/vendoring/) third party dependencies for all comma projects.

all of our projects are python projects, so each of these gets packaged as a pip project.

this vendoring serves a few goals:
- all dependencies are centrally managed here
- we can slim them down to only what we need
- all platforms get the same versions installed
- tighter control of distribution for fast installs (e.g. Ubuntu's `apt-get` is slow)

motivations for this approach:
- `apt-get` is slow
- `apt-get` updates 
- `apt-get` pacakge versions don't match `brew` versions
- `apt-get` doesn't comw with Arch Linux
- `apt-get` doesn't always have the exact package we need
- `apt-get` packages are often larger than we need

`uv`, as opposed to `apt-get`, `brew`, and friends, is fast and already used in our projects since we use Python.

we target the following platforms:
- Linux x86_64
- Linux aarch64
- Darwin aarch64 (Apple Silicon)

contributions welcome for other platforms!


usage:
```python
dependences = [
  "capnproto @ git+https://github.com/commaai/dependencies.git@more-vendor#subdirectory=capnproto",
  "ffmpeg @ git+https://github.com/commaai/dependencies.git@more-vendor#subdirectory=ffmpeg",
]
```

## packages

| package           | description                                                              |
|-------------------|--------------------------------------------------------------------------|
| gcc-arm-none-eabi | builds [panda](https://github.com/commaai/panda) firmware for STM32 MCUs |
| capnproto         | message serialization for openpilot                                      |
| ffmpeg            | video encode and decode for openpilot                                    |
