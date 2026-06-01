#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "tickoni-policy: $1" >&2
  exit 1
}

for doc in doc/tickoni-interface-contract.md \
           doc/tickoni-identity-and-packaging.md \
           doc/tickoni-cutover-record.md; do
  [[ -f "$doc" ]] || fail "$doc must exist"
done

if ! rg -n '^char const \* FD_BINARY_NAME = "tickoni";$' src/app/firedancer/main.c >/dev/null; then
  fail "src/app/firedancer/main.c must keep tickoni as canonical runtime binary name"
fi

if ! rg -n '^\.PHONY: tickoni firedancer$' src/app/firedancer/Local.mk >/dev/null; then
  fail "src/app/firedancer/Local.mk must keep tickoni/firedancer phony targets"
fi

if ! rg -n '^\$\(OBJDIR\)/bin/firedancer: \$\(OBJDIR\)/bin/tickoni$' src/app/firedancer/Local.mk >/dev/null; then
  fail "firedancer compatibility target must alias to tickoni"
fi

if ! rg -n 'TICKONI_CONFIG_TOML' src/app/shared/boot/fd_boot.c src/app/shared_dev/boot/fd_dev_boot.c >/dev/null; then
  fail "Tickoni config env var must be supported in boot paths"
fi

if ! rg -n 'FIREDANCER_CONFIG_TOML is deprecated' src/app/shared/boot/fd_boot.c src/app/shared_dev/boot/fd_dev_boot.c >/dev/null; then
  fail "legacy FIREDANCER_CONFIG_TOML deprecation fallback must remain"
fi

for path in src/app/shared/commands/version.c \
            src/disco/gui/fd_gui_tile.c \
            src/discof/rpc/fd_rpc_tile.c \
            src/disco/bundle/fd_bundle_tile.c; do
  if ! rg -n 'tickoni_version_string' "$path" >/dev/null; then
    fail "$path must use tickoni runtime version identity"
  fi
done

if ! rg -n 'tickoni-v' contrib/tag-release.py >/dev/null; then
  fail "contrib/tag-release.py must emit tickoni-v canonical tags"
fi

if ! rg -n '/data/tickoni' contrib/containers/*.dockerfile contrib/containers/README.md >/dev/null; then
  fail "container build assets must use /data/tickoni identity"
fi

echo "tickoni-policy: OK"
