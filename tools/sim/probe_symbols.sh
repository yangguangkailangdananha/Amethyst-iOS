#!/usr/bin/env bash
set -euo pipefail
OUT="${RUNNER_TEMP:-/tmp}/mc26-sim"
mkdir -p "$OUT"
cd "$OUT"
cat > probe.c <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
void probe(void) { printf("probe Amethyst_GetHost=%p\n", dlsym(RTLD_DEFAULT, "Amethyst_GetHost")); fflush(stdout); }
EOF
cat > hostapp.c <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
__attribute__((visibility("default"))) void Amethyst_GetHost(void) {}
int main(void) {
    void *h = dlopen("./libprobe.dylib", RTLD_NOW);
    if (!h) { printf("dlopen failed: %s\n", dlerror()); return 1; }
    void (*fn)(void) = (void (*)(void))dlsym(h, "probe");
    fn();
    return 0;
}
EOF
clang -dynamiclib -o libprobe.dylib probe.c
clang -o hostapp hostapp.c -Wl,-export_dynamic
./hostapp > probe.log 2>&1 || true
cat probe.log
