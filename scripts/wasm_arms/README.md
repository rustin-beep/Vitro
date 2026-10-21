# wasm_arms — five-way duel infrastructure (ISS-199)

One command from the Vitro repo root:

    python scripts/wasm_arms/run_duel.py --wasmoon-src <wasmoon-checkout> [--skip-clang] [--limit N]

Pipeline: gateway dual-flavor build -> sanity both wasm host arms -> generate
per-case NDJSON from corpus/baseline -> wasmoon x wasmtime dual-arm duel ->
optional clang three-way arbitration. Verdict buckets mirror corpus_fuzz
(AGREE / HOST_DIVERGENCE / TIMEOUT / ARM-FAIL).

Layout:
  wasmoon_arm/    MoonBit host driving the gateway via wasmoon (built from a
                  wasmoon SOURCE checkout pinned with --wasmoon-src; never
                  link mooncakes wasmoon@0.17.0 — that build has the
                  type-registration hang fixed in upstream #552)
  wasmtime_arm/   wasmtime host (Python, wasmtime-py; the Go binding build on
                  Windows was abandoned — see cgo_stub.go notes)
  duel/           driver scripts: runner.py (dual-arm duel), arb.py (three-way
                  arbitration vs clang), duel.exe (legacy single binary)

Platform notes:
  - wasmtime arm: `pip install wasmtime` (prebuilt wheel, no linking).
  - wasmoon arm on Windows: requires vcvars64 + the wasmoon-cl driver
    (scripts/msvc/setup.ps1 pattern) because MSVC cl rejects C11 atomics;
    run_duel.py generates the moon.work wiring for you.
  - wasmoon arm on macOS/Linux: plain `moon build --target native` (branch
    written against upstream CI layout, not yet exercised on a Unix host).
  - the wasmtime-go static lib in the global GOMODCACHE was objcopy-patched
    during the Go-binding attempt (symbol __intrinsic_setjmpex renamed);
    unrelated projects using wasmtime-go on this machine should be aware.

Known harness gaps (tracked for the corpus defense, not engine bugs):
  stdin feeding (gateway input.feed unused), line-based frame protocol breaks
  on binary output bytes (0x85/0x0B/0x0C), CRLF normalization already applied
  in arb.py, nested headers now collected recursively.
