const char *tickoni_compiler_version(void) {
#if defined(__VERSION__)
    return __VERSION__;
#else
    return "unknown";
#endif
}
