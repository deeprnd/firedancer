// Minimal libuuid stub for Windows.
// Windows prebuilt FD libs (from CI) carry RocksDB metadata that references
// libuuid.a. This stub provides the uuid_generate symbol the linker expects.
// macOS/Linux prebuilt libs do not carry this dependency.

#include <string.h>

void uuid_generate(unsigned char out[16]) {
    // Opaque 16-byte placeholder — UUID handling happens at a higher layer.
    memset(out, 0, 16);
}
