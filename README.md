# dependencies

a central repo for managing and vendoring third party dependencies for all comma projects.

all of our projects are python projects, so each of these gets packaged as a pip project.

this vendoring serves a few goals:
- all dependencies are centrally managed here
- we can slim them down to only what we need
- all platforms get the same versions installed
- tighter control of distribution for fast installs (e.g. Ubuntu's `apt-get` is slow)

we target the following platforms:
- Linux x86_64 (glibc)
- Linux aarch64 (glibc)
- Darwin aarch64 (Apple Silicon)

contributions welcome for other platforms!
