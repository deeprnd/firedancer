#!/usr/bin/env bash

# tk_expand_home expands a leading tilde in a path.
tk_expand_home() {
  local path="$1"

  case "$path" in
    "~")   printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${path:2}" ;;
    *)      printf '%s\n' "$path" ;;
  esac
}

# tk_resolve_llama_cpp_dir resolves the llama.cpp checkout directory.
#
# Resolution order:
# 1. TK_LLAMA_CPP_DIR, when set
# 2. First existing directory from the built-in candidates below
# 3. Fallback default path for fresh clones
#
# The function prints the resolved directory to stdout.
tk_resolve_llama_cpp_dir() {
  if [[ -n "${TK_LLAMA_CPP_DIR:-}" ]]; then
    tk_expand_home "$TK_LLAMA_CPP_DIR"
    return 0
  fi

  local candidate
  for candidate in \
    "$HOME/work/models/llama.cpp" \
    "$HOME/work/git/llama.cpp"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$HOME/work/models/llama.cpp"
}
