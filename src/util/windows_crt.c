/* _fltused is needed by the Windows CRT when float constants are referenced.
 * This symbol is compiled unconditionally because Zig always includes this
 * file when targeting Windows — the preprocessor guard is unnecessary and
 * can fail if Zig doesn't propagate FD_HAS_WINDOWS to its C compiler. */
int _fltused = 0;
