/* _fltused is needed by the Windows CRT when float constants are referenced.
 * This stub is built by both Zig (from src/tickoni/c_abi/shim/windows_crt.c)
 * and by the Makefile (from src/util/windows_crt.c) for the fd_util library.
 * The symbol is trivial — zero-initialized int — so duplication is safe. */
int _fltused = 0;
