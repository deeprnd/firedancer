---
author: deeprnd
date: 2026-07-02
---

**Q: A systems library exposes a hot-path function as `static inline` in its
headers. Something outside that library, in a different compiled language,
needs to call it through FFI. `static inline` has no linkable symbol —
`nm` on the built archive confirms nothing's there to bind to. What are the
actual options?**

There are three, and they trade off real reuse against real risk
differently enough that it's worth being precise about which one you're
actually choosing.

**Option 1: reimplement the logic in the calling language.** Read the
`static inline` body and write an equivalent function on the calling side.
Nothing in the original library changes, no new build artifacts appear on
its side, and the calling side owns one extra file. The cost is that this
is now two independent copies of the same behavior. Correctness depends on
a careful, line-by-line translation, and needs tests pinned to the exact
byte layout / semantics of the original to catch drift. And it never
self-updates: if the original function's logic changes upstream, the copy
goes silently stale until someone notices and re-translates it by hand.
This option trades reuse for isolation — you get to touch nothing upstream,
but you also don't actually get the upstream logic running, just a copy of
it.

**Option 2: add a thin non-inline wrapper in a brand-new translation unit.**
One tiny function, owned entirely by the calling side, that does nothing
but call the real `static inline` function and return its result. This
produces a real, exported symbol without changing a single byte of the
original library — the wrapper is a new file, not an edit. The original
logic runs unmodified; the only new code is a pass-through with no
algorithm in it. The cost is small: an extra symbol name that isn't the
original API's name, one more small compiled unit, and — if the original
function is one of several hand-tuned variants selected by preprocessor
conditionals (e.g. a scalar version plus SIMD variants picked by target
CPU features) — a conscious choice of which variant the wrapper targets,
since the calling language doesn't get that dispatch for free just by
wrapping one of them.

Concretely: say the library ships `fastmath.h` with

```c
/* fastmath.h — untouched */
static inline uint64_t
fm_hash_mix( uint64_t x, uint64_t seed ) {
  x ^= seed;
  x *= 0x9E3779B97F4A7C15ULL;
  x ^= x >> 32;
  return x;
}
```

The calling side adds one new file, `fastmath_shim.c`, that it owns:

```c
/* fastmath_shim.c — new file; fastmath.h is not edited */
#include "fastmath.h"

uint64_t
shim_fm_hash_mix( uint64_t x, uint64_t seed ) {
  return fm_hash_mix( x, seed );
}
```

Once that's compiled and linked in, the calling language just declares the
shim's symbol and calls it like any other external function — here, from
Zig:

```zig
// extern fn bound against the compiled fastmath_shim.o
pub extern fn shim_fm_hash_mix(x: u64, seed: u64) u64;

pub fn hashKey(key: u64) u64 {
    return shim_fm_hash_mix(key, 0xA5A5_A5A5_A5A5_A5A5);
}
```

`fastmath.h` never changes. `fm_hash_mix` keeps getting inlined exactly as
before everywhere the original library already calls it. `shim_fm_hash_mix`
is the only new symbol anywhere, it contains no logic of its own, and it's
the one thing Zig actually binds to.

The wrapper's boundary doesn't have to resolve to a single body, either. If
the calling language needs to run on platforms the original library was
never written for at all — no header, no implementation, nothing there to
wrap or un-hide — the same exported name can stay the calling side's one
stable interface while its body is conditionally compiled per target: a
genuine pass-through to the `static inline` function where that library
exists, and freshly-authored logic using each other platform's own native
equivalent where it doesn't.

```c
/* fastmath_shim.c — one exported name, body varies by target */
uint64_t
shim_fm_hash_mix( uint64_t x, uint64_t seed ) {
#if defined(TARGET_HAS_FASTMATH_H)
  return fm_hash_mix( x, seed );                 /* real pass-through, as above */
#else
  return other_platform_native_mix( x, seed );    /* freshly written for this target */
#endif
}
```

The calling side still declares exactly one `extern fn shim_fm_hash_mix(...)`
and never branches on target platform at the call site — all of the
platform variance stays inside this one file. That's a legitimate
application of the Bridge pattern: fix the abstraction (name and signature)
once, and let the implementation vary underneath it.

Worth being precise about what this actually buys, though: it only produces
real reuse on the platform where the original library exists. On every
other target, the wrapper's body is brand-new code — the same amount of new
logic Option 1 would require, just written in the wrapper's language instead
of the calling language. So this isn't "Option 2 everywhere" so much as
Option 2 on the one platform that has something to wrap, and Option 1 on
every other platform, deliberately unified behind one stable name so the
calling side never has to know the difference. The real design choice is
*where the platform dispatch lives*: inside the wrapper (shown above — call
sites on the calling side stay maximally simple, but new logic for other
platforms is now written in the wrapper's language) or on the calling side
itself (branch on target platform at or near each call site, keeping all
newly-authored logic in the calling language and reserving the wrapper for
only the one platform it's genuinely wrapping something on). Option 3 can't
be stretched this way at all — there's no existing definition to un-hide on
a platform where the original library was never written in the first place.

**Option 3: change the source's storage-class/visibility qualifier — never
its signature.** "Change the header" can mean two very different edits, and
only one of them actually belongs in this list:

- *3a — change the signature.* Add, remove, or retype parameters. This
  cascades: every existing call site in the original library has to be
  updated to match. Whatever problem this solves, it isn't really "make
  this callable from another language" — that's a much bigger design
  change riding along for the ride, and should be evaluated on its own
  merits, not adopted as a side effect of an FFI need. It's listed here
  only to rule it out explicitly, since "just edit the header" can sound
  like it includes this. It doesn't, and it shouldn't.

- *3b — change only the storage-class/visibility qualifier* (e.g. drop
  `static`, keep `inline`). Every parameter, every argument, every call
  site's source text stays exactly as it was — this is a pure visibility
  change, not a signature change, and that distinction is the whole reason
  it's viable. It's much closer to free than it looks at first: whether a
  call gets inlined is governed by the `inline` hint and the optimizer's
  own heuristics, not by the visibility qualifier, so existing call sites
  in the original library see zero behavior change and don't need to be
  touched at all. It also doesn't create a multiple-definition linker
  error, which is the failure mode people reach for as an objection here —
  that only happens if `inline` is dropped too, turning the function into
  an ordinary definition sitting in a header included by many files. Left
  as `inline` (just not `static`), the original library's own files still
  only see a definition that, by itself, never emits an external symbol —
  there's nothing for a second copy to collide with. And if the function is
  one of several separately-named hot-path variants (say, a generic scalar
  body plus SIMD-specialized siblings picked by preprocessor conditionals),
  touching one variant's qualifier doesn't touch the others — they're
  independent definitions with independent names, untouched by this edit.

  The catch: a bare `inline` (no `static`, no `extern`) still doesn't by
  itself guarantee a real address exists anywhere for an outside caller to
  bind to — standards-conforming toolchains only materialize a real symbol
  for an inline definition when something, somewhere, explicitly forces one
  external instantiation. That instantiation can be done entirely from the
  calling side: an `extern` declaration with no body, in a new file the
  calling side owns, tells the compiler to materialize exactly one real,
  callable, externally-visible copy using the body it already saw from the
  (now non-static) header. So the *only* edit to the original library ends
  up being the one-word qualifier removal, once per function; no other file
  in the original library needs to change, and the caller ends up binding
  to the exact original function name — more literal reuse than a wrapper
  (option 2), since there's no pass-through function standing in for it.

  What's genuinely still true, and not free: it's a small, mechanical,
  permanent diff against files you don't own, which has to be reconciled
  every time those files are refreshed from whatever produces them
  upstream — low conflict probability for a single-keyword change in
  practice, but a recurring maintenance item forever, not a one-time cost.
  It also needs an actual compile check, not just a read of the header —
  attributes like "this function is pure/const" and whatever warning flags
  the original library builds with can interact with the
  extern-instantiation trick in ways worth verifying rather than assuming.

One more thing worth being honest about if the calling side is also trying
to run on a platform the original library doesn't support at all: 3b is a
non-starter there, full stop, and — unlike option 2 — there's no bridge
variant that rescues it. Nothing about "remove one word, add one extern
declaration" survives when there's no existing definition anywhere to
un-hide. That's worth stating plainly rather than discovering it mid-port.

It also tends to matter less in practice than it first sounds like it
would. A function reused via 3b was, by construction, something the calling
side deliberately chose *not* to rewrite even at zero cost to do so — which
usually means it's genuinely hot-path or otherwise carries real
implementation weight worth preserving exactly. That's precisely the kind
of code a portable variant on another platform is least likely to need
verbatim; a lighter-weight port usually trades that performance-critical
core away rather than tries to carry it along. And separately, going
looking for "the 2-3 platform-specific calls buried inside an otherwise
shared function" as the thing to port tends to overestimate the problem:
functions that reach for 3b are usually narrow, single-purpose wrappers
around one specific primitive to begin with, where the entire function body
already *is* the platform-specific call, with no shared logic mixed in to
carefully extract. In that shape, porting isn't surgery on a shared
function — it's writing one small, self-contained sibling per target and
dispatching to it at the boundary, while anything genuinely
platform-agnostic living nearby (data structures, formatting, pure
computation) doesn't need to move or duplicate at all.

**So, how to choose?** If you don't control the upstream project and don't
track its changes closely, options 1 and 2 avoid taking on any upstream-sync
burden at all — and of the two, prefer 2 over 1 whenever you want the real
compiled logic to execute rather than a hand-copied equivalent, since the
extra cost of 2 over 1 is usually small (one wrapper file vs. one mirror
file) while the correctness guarantee is much stronger (real logic running,
not a translation of it). If you do vendor or closely track the upstream
project and already treat sync diffs as routine, 3b gets you the most
literal reuse available — the caller binds to the exact original symbol,
not a proxy for it — at the cost of a small, recurring, mechanical patch
that has to be carried forward. 3a is essentially never the right tool
purely to solve an FFI/linkage problem; if an actual signature change is
warranted, make that call independently of the FFI question.

**Decision.** For this codebase, option 2 is the standing default whenever
a `static inline` function needs FFI reuse — not just "prefer 2 over 1" as
a tiebreaker, but the go-to choice, with 1 and 3 reserved for cases that
specifically don't fit it.

The GoF framing makes the choice sharper than "which is cheaper." The
single-body form of option 2 is a **Proxy** — a transparent stand-in whose
only job is crossing the boundary that keeps the real function from being
independently callable. Its cross-platform form — one exported name, body
selected per target, one branch a genuine pass-through and the others
freshly written — is a textbook **Bridge**: the abstraction (name and
signature) is decoupled from the implementation (which body actually
runs), and the two can be extended independently. Option 3 has no
equivalent in either shape. It never introduces a second entity to begin
with — there's nothing to decouple, because there's only ever one
implementation, viewed through two different visibility levels. That's why
option 3 cannot be extended to a platform where the original library was
never written, while option 2's Bridge form can, cleanly, because it
already has the abstraction/implementor split option 3 lacks.

That extensibility is the deciding factor, not a hypothetical one. The
moment the calling side needs to run on a platform the original library
doesn't support at all — and for real systems software that moment tends
to arrive eventually, not never — option 3 is disqualified outright, with
no graceful migration path; the wrapper would be starting from scratch
anyway at that point. Choosing option 2 as the default now means that
migration never has to happen: every function reused this way already
sits behind a stable name a future platform-specific body can be added to
without touching any existing caller.

**Deviations.** Not everything that needs a platform-specific answer
arrives via this problem in the first place, and forcing it into the same
shape would be a mistake worth naming rather than papering over. Some
functions are already real, ordinarily-linkable symbols in the original
library — no `static inline` involved, nothing to wrap for linkage reasons
at all — but have no equivalent primitive or concept on other platforms
whatsoever. `fd_sandbox_enter` (Firedancer's seccomp/Landlock/namespace
sandbox entry point) is exactly this: already a real linkable symbol
today, so option 3's premise doesn't even apply to it, and there is no
existing implementation anywhere else to reuse via option 2's pass-through
branch either — its eventual port needs a Bridge-shaped abstraction where
every branch except Linux's is freshly authored from the target platform's
own security primitives, not the light lift this decision otherwise
implies for most functions. Other Linux-only functions not yet identified
may turn out to have this same shape rather than the static-inline-mirror
shape this document started from, and each one should be checked rather
than assumed.
