# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`modernc.org/libquickjs` is a **pure Go embeddable JavaScript engine** produced by
transpiling Bellard's [QuickJS](https://bellard.org/quickjs/) (C) to Go with
[`ccgo`](https://pkg.go.dev/modernc.org/ccgo/v4). It is *not* hand-written Go —
almost all of the code is machine-generated. This package exposes the raw,
low-level C ABI. The idiomatic Go wrapper lives in a separate repo,
[`modernc.org/quickjs`](https://pkg.go.dev/modernc.org/quickjs).

Pinned upstream: QuickJS commit `3d5e064…` (release 2026-06-04), test262 commit
`5c82069…`. The hashes are duplicated in several places that must stay in sync
when bumping: `generator.go` (`qjsCommit`, `test262Commit`), `Makefile`
(`QJS_ZIP`, `TEST262_ZIP`), `builder.json` (the `download` URLs), and — for
test262 only — `all_test.go` (`hash262`, used to unzip the suite). The release
date also appears in `libquickjs.go`'s package doc.

## Commands

Tests pass `-vet=off` because `go vet` chokes on the ~180K-line generated files;
keep that flag when running tests manually.

```sh
make editor      # fast compile-check loop: gofmt + `go test -c` (no run) + build generator
make shorttest   # go test -short  (skips the heavy Test262 suite)
make test        # full suite incl. Test262: go test -vet=off -v -timeout 24h -failfast
make bench       # microbenchmarks (BenchmarkMicro); `make cpu` adds a pprof profile
make generate    # regenerate ccgo_*.go for the CURRENT GOOS/GOARCH (see below)
make download    # fetch the pinned QuickJS + test262 zips (prerequisite for generate)
make nuke        # clean + drop ./tmp/ and ./test262/
```

Running individual tests — `-run` is an unanchored regexp, so a bare `-run Test`
or `-run Test2` **also selects `Test262`** and kicks off a multi-hour conformance
run; anchor with `$`:

- `go test -vet=off -run 'Test$'` — evaluates the five `testdata/tests/*.js` files listed in `Test`.
- `go test -vet=off -run 'Test2$'` — arithmetic / `Date.getYear` eval cases (= `make test2`).
- `go test -vet=off -run Test262` — full ECMAScript conformance run (needs the test262 zip).
- `go test -vet=off -run Test262 -f test262/test/<...>.js` — one test262 file.

Custom flags parsed in `TestMain`: `-re <regexp>` filters subtests, `-keep` keeps
the unpacked `test262/` dir (= `make ktest`), `-f <file>` selects a single test262
file, `-xtags <tags>` (or `$XTAGS`) sets build tags for the run-test262 binary.

## Architecture

**Generated vs. hand-written.** The bulk of the repo is the `ccgo_<goos>_<goarch>.go`
files (~180K lines / ~6MB each), one per platform, each marked `DO NOT EDIT` and
carrying a `//go:build <goos> && <goarch>` constraint (`ccgo_windows.go` covers
`windows && (amd64 || arm64)`). **Never hand-edit these — regenerate instead.**
Fixes to transpilation belong in the patches (`internal/patch/quickjs.diff`,
`internal/patch/test262.diff`) or the generator, not in the output.

The only hand-written package files are small: `libquickjs.go` (package doc,
`init`, `MaxStackSlots`, the `_js_check_stack_overflow` override), `etc.go`
(`origin`/`todo`/`trc` debug helpers), `types_{linux,other}.go` (the `Size_t`
alias), `libquickjs_{freebsd,windows}.go` (platform libc stubs), and
`{32,64}_test.go` (test-side `TJSValue` decode helpers — `tag`, `jsvToFloat64`,
`jsvToInt32` — split by build tag `386 || arm` vs. the rest, because 32-bit uses
NaN boxing and 64-bit a struct; the 64-bit `jsvToInt32` deliberately reads the
union as a `uint64` so it works on big-endian s390x too). `internal/run-test262`
mirrors the same pattern: transpiled `ccgo_*.go` plus hand-written `etc.go`,
`patch.go` (its own `_js_check_stack_overflow`), `patch_freebsd.go`,
`patch_windows.go`.

**The generation pipeline** (`generator.go`, `//go:build ignore`, run via
`go generate` / `make generate`): unzips the pinned QuickJS + test262 sources into
`tmp/` → applies the `internal/patch/*.diff` patches via `git apply` → builds
QuickJS's `libquickjs.a` and the native `run-test262` through ccgo's `-exec make`
→ transpiles the archive into `ccgo_<goos>_<goarch>.go` → post-processes
identifiers with `sed` → copies the transpiled runner into `internal/run-test262/`.
`make generate` only emits the file for the host platform; per-platform files are
produced by the modernc builder farm (the `… auto generate` commits), driven by
`builder.json` and the per-arch `go.mod` snapshots in `internal/autogen/`.

**Windows is the exception.** `ccgo_windows.go` serves both windows arches but has
no native builder, so nothing would refresh it on a QuickJS bump — it once went
~9 months stale. A `make generate` run on **linux/amd64** therefore also
cross-generates it (`make w64`) and snapshots `go.mod` into
`internal/autogen/windows_{amd64,arm64}.mod`; set `GO_GENERATE_NOWIN=1` to skip
that on hosts without the toolchain. The cross compiler must be **llvm-mingw
(clang)** — GNU mingw's `<_mingw.h>` uses `__int128` in a way ccgo cannot
type-check, so a GNU `x86_64-w64-mingw32-gcc` on `$PATH` is rejected. `w64gcc()`
probes `$LLVM_MINGW_BIN`, `$HOME/bin/llvm/bin`, the newest
`$HOME/bin/llvm-mingw-*/bin`, then `$PATH`. Toolchain drift surfaces as
missing/renamed libc symbols; fix by adding stubs or `libc` forwarders to
`libquickjs_windows.go` and `internal/run-test262/patch_windows.go`.

**Naming conventions** come from the ccgo `--prefix-*` flags plus `sed` renames in
`generator.go`. The public QuickJS `JS_*` C functions become **`XJS_*`** in Go
(e.g. `XJS_NewRuntime`, `XJS_Eval`, `XFreeValue`); tagged structs get a `T` prefix
(`TJSValue`, `TJSRuntime`), enum constants an `E` prefix (`EJS_TAG_INT`), macros an
`M` prefix (`MJS_EVAL_TYPE_GLOBAL`), and internal symbols a `_` prefix. There are
no idiomatic Go types here — you call the C ABI directly.

**libc / TLS.** Every generated function takes a `*libc.TLS` (execution context)
from `modernc.org/libc` as its first argument, and memory is managed manually
(`libc.CString`, `libc.Xfree`, `libc.GoString`). `all_test.go`'s `eval` helpers are
the canonical example of driving the raw API: `NewTLS` → `XJS_NewRuntime` →
`XJS_NewContext` → `XJS_Eval` → inspect the `TJSValue` tag → free everything.

**Stack-overflow detection is special.** ccgo is invoked with
`-hide js_check_stack_overflow`, so QuickJS's native C stack check is dropped and
replaced by the hand-written `_js_check_stack_overflow` in `libquickjs.go`, which
compares `tls.StackSlots()` against a limit (the runtime's `Fstack_size`, defaulting
to `MaxStackSlots = 5000`). This matters because transpiled recursion runs on the Go
stack; the constant's comments record the tuning history. `Fstack_size` counts TLS
stack slots, not bytes, so `internal/patch/quickjs.diff` makes `JS_NewRuntime2` leave
it 0. Upstream sets 1 MB, meant as bytes, which read as slots was no limit at all:
infinite JS recursion died with Go's `fatal error: stack overflow`
(`TestStackOverflow`). `internal/run-test262/patch.go` has its own check that always
uses `MaxStackSlots`, which is why test262 never noticed.

**`lre_exec` skips where a regexp cannot start to match.** The bytecode of a
regexp that is not sticky starts with a loop that tries every position, about 25 ns
a position in Go. A `quickjs.diff` hunk in `libregexp.c` (`lre_skip_op`,
`lre_skip_find`) finds the positions that can start a match when the regexp begins
with a character, a class or `^`, and runs the bytecode from there. It checks the loop
as `lre_compile` writes it and falls back to it when that differs, so a QuickJS bump
can silently turn it off: `TestRegexpInterrupt` notices, and `TestRegexpCorpus` pins
the results to what the engine gave without the skip.

## test262 conformance

`Test262` unpacks the pinned suite into `./test262/`, patches it with
`internal/patch/test262.diff`, builds `internal/run-test262` (itself a transpiled C
program) and runs it. It parses the runner's `Result:` line and **fails only on
*new* errors** relative to the committed baseline `test262_errors.txt`, so a
QuickJS bump that changes conformance means updating that file. (`test262_report.txt`
is a run artifact and is gitignored — don't try to commit it.) A missing test262
zip makes the test skip, except on the builder farm (`$MODERNC_BUILDER` set), where
it is fatal.

Two per-target override mechanisms exist and are easy to confuse:

- **`testdata/test262_<goos>_<goarch>.conf` — auto-generated, DO NOT EDIT.**
  `genTargetConf` in `generator.go` runs the freshly built *native C* QuickJS
  reference against the base `testdata/test262.conf`, and records the tests that
  fail on this hardware but are absent from `test262_errors.txt` (libm ULP
  differences and similar). It rewrites the file verbatim from the base conf on
  every `make generate` — inserting the block before the `[tests]` section, which
  the base conf must contain — and deletes it when there is nothing to exclude, so
  the overrides cannot silently go stale. Skipped for cross builds (windows, and
  any `GOOS/GOARCH` ≠ host), which therefore never get one.
- **`testdata/test262_exclude_<goos>_<goarch>` — hand-curated.** Tests that fail
  **only in the Go build** (modernc `libc` vs. system libc), which the native
  reference run above cannot see by construction. Passed to the runner via `-x`.
  Keep the existing per-entry comments explaining *why* each is excluded.

`Test262` prefers `testdata/test262_<goos>_<goarch>.conf` over the base
`testdata/test262.conf` and copies the winner to `./test262.conf`; the exclude
file is likewise copied into the cwd and passed **by bare basename**, because
run-test262 resolves namelist entries relative to the file's own directory (a
`testdata/` prefix would be prepended to every entry and nothing would match).
Both root-level copies are gitignored build artifacts — always edit the
`testdata/` originals.

## Supported platforms

darwin/{amd64,arm64}, freebsd/{amd64,arm64},
linux/{386,amd64,arm,arm64,loong64,ppc64le,riscv64,s390x}, windows/{amd64,arm64}.
Building for a platform requires its `ccgo_<goos>_<goarch>.go` to be present in the
repo.
