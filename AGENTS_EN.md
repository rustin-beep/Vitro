# Vitro Agent Guide (English Summary)

> Details are maintained in Chinese; this file is routing-only.

## Repository zones (Rust oracle zone retired & deleted on 2026-10-05)

- **MoonBit active zone** — `moonbit/` (MoonBit workspace; published on mooncakes as `vitro/engine`). The **only implementation zone**; all new development happens here. Handbook: [`moonbit/AGENTS.md`](moonbit/AGENTS.md) (**read on demand**: build commands / language & toolchain pitfalls / coding disciplines / publish flow); master plan: `docs/current/01-定位与路线/MoonBit迁移总计划.md`.
- **Rust oracle zone (retired)** — the former `native/` was **physically deleted** on 2026-10-05 (S9 step ④). Archive: tag `rust-oracle-freeze`, branch `frozen-oracle-snapshot`, and git history. `scripts/` and `.github/` are the language-neutral Go defense layer with no zone handbook.

**Routing**: touching `moonbit/` → read `moonbit/AGENTS.md` first; docs/discussion only → read no handbook.

**MoonBit package naming (decided 2026-09-19)**: module name = `vitro/engine` (mooncakes owner `vitro`); every package is `vitro/engine/<pkg>` (e.g. `vitro/engine/diag`) in `moon.pkg` imports, generator-script comments, and `.mbti` interfaces. Plan documents may abbreviate to `vitro/<pkg>`; code and config must not.

## Global disciplines (language-neutral)

Chinese output required; no git commits without permission; **measurement over speculation with a single source of truth** (verify by running commands / reading code; reports are leads, not evidence; numbers reconcile against `reports/facts.json` — CI runs `facts check --strict`); honest recording of any divergence from Clang; red→green discipline (a failing test case precedes every fix, commit messages reference the case name; guard scripts must be proven able to fail — J9); never reference `docs/archive/`; new docs go under `docs/current/<category>/` with Chinese filenames and a synced `docs/README.md` index; judgment scripts default to Go with zero third-party dependencies and externalized JSON rules.

## Current phase & archive

S9 in progress: the Rust oracle zone was deleted on 2026-10-05 (archive = tag `rust-oracle-freeze` + branch `frozen-oracle-snapshot` + git history; 16 exploration docs live in commit `917251e`). Remaining: S9 rulings execution + unlocked fix backlog (#3–#24). Schedule authority: master plan §10.
