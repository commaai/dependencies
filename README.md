# dependencies

an attempt for minimal packaging of openpilot dependencies

all of our projects are python projects, so each of these gets packaged as a pip project

this vendoring serves a few goals:
- all dependencies are centrally managed here
- all platforms get the same versions installed
- tighter control of distribution for fast installs (e.g. Ubuntu's `apt-get` is super slow)
- minimizing the install size. for example, gcc-arm-none-eabi ships with toolchains for ARM, however we only need the one for panda

---

we target the following platforms:
- Linux x86_64 (glibc)
- Linux aarch64 (glibc)
- Darwin aarch64 (Apple Silicon)

contributions welcome for other platforms!
