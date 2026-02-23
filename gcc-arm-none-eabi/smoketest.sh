#!/usr/bin/env bash
set -euo pipefail

echo "--- gcc-arm-none-eabi smoketest ---"

# 1. Version check
arm-none-eabi-gcc --version

# 2. Cross-compile a tiny C file targeting Cortex-M7
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/hello.c" <<'EOF'
volatile int counter;
int main(void) {
    counter = 42;
    while (1) {}
}
EOF

arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -nostdlib -o "$TMPDIR/hello.elf" "$TMPDIR/hello.c"
arm-none-eabi-size "$TMPDIR/hello.elf"

echo "gcc-arm-none-eabi: OK"
