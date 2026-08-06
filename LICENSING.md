# Tickoni Licensing

Tickoni is a mixed-license repository.

## Apache-2.0 components

Unless expressly stated otherwise, the following are licensed under
the Apache License, Version 2.0:

- the Firedancer-derived execution infrastructure;
- the Tickoni Zig runtime;
- the Tickoni CLI;
- `tkapi` schemas and protocol definitions;
- non-UI SDKs and generated clients;
- general build, test, and technical documentation.

The Apache-2.0 license text is contained in `LICENSE`.

## GPL-3.0-only terminal

The official Tickoni desktop terminal uses Qt components under Qt's
open-source GPLv3 terms.

All source code under `src/tickoni/ui/`, including C++, QML,
terminal-specific CMake files, terminal resources, and terminal tests,
is licensed under GPL-3.0-only unless a file expressly states
otherwise.

The GPL-3.0-only license text is contained in
`LICENSES/GPL-3.0-only.txt`.

The Tickoni runtime and terminal are separate programs. The terminal
communicates with the runtime through the versioned `tkapi`
HTTP/WebSocket interface. The runtime and CLI remain Apache-2.0.

Apache-2.0 libraries, schemas, or generated clients used by the
terminal retain their original Apache-2.0 licensing. The distributed
terminal combination is provided under GPL-3.0-only.

## Creative content

Tickoni lore, characters, narrative release material, illustrations,
and related creative content are governed by `CONTENT-LICENSE.md`.

They are not licensed under Apache-2.0 or GPL-3.0-only.

## Third-party software

Qt and other dependencies retain their respective copyrights and
licenses.

See `NOTICE` for applicable attributions.