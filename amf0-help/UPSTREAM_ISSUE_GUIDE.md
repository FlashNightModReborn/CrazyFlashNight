# Upstream issue handoff guide

**Target**: <https://github.com/ruffle-rs/rust-flash-lso>  
**Checked**: 2026-05-22.

## Current upstream state

- There is already an open upstream issue: `ruffle-rs/rust-flash-lso#72`, "AMF0 Reference generation seems broken".
- The repository's `.github` directory currently contains `workflows/` and `dependabot.yml`; no issue template was visible.
- Recommended action: comment on `#72` with our minimal reproducer instead of opening a duplicate issue.

## What to post

Paste the body of [`ISSUE.md`](ISSUE.md) as a comment on `#72`.

If GitHub or the maintainers ask for files, submit only the minimal public repro set:

| Purpose | File |
|---|---|
| Main comment body | `amf0-help/ISSUE.md` |
| Runnable upstream-style example | `amf0-help/sol_parser/examples/flwriter_probe.rs` |
| Small generated SOL from `flash-lso` writer | `amf0-help/probe_sols/flwriter_probe.sol` |
| Optional independent byte decoder | `amf0-help/amf0_probe.py` |
| Optional Adobe Flash controlled fixtures | `amf0-help/probe_sols/amf0probe_self.sol`, `amf0-help/probe_sols/amf0probe_nested.sol`, `amf0-help/probe_sols/amf0probe_root.sol` |

Do **not** submit project-internal material unless explicitly needed:

- `launcher/native/sol_parser/*`
- `launcher/README.md`
- `scripts/优化随笔/Flash-SOL-AMF0引用基址实证澄清.md`
- `amf0-help/sol_parser/tests/fixtures/real_flash_v3.sol`

The real game fixture is useful internally but unnecessary upstream; the issue can be proven with the three-object writer example.

## Pre-post verification

From the repo root:

```powershell
chcp.com 65001 | Out-Null
cargo run --example flwriter_probe
cargo test
```

Run those in `amf0-help/sol_parser/`. Expected writer output:

```text
A (1st complex object) -> Reference(0)
B (2nd complex object) -> Reference(3)
C (3rd complex object) -> Reference(4)
```

Optional independent decode:

```powershell
chcp.com 65001 | Out-Null
python amf0_probe.py probe_sols/flwriter_probe.sol
```

Expected key point: `C.ptr_to_B` carries raw `3`, while the AMF0 complex-object table is `[A, B, C]`.

## Posting flow

1. Sign in to GitHub.
2. Open <https://github.com/ruffle-rs/rust-flash-lso/issues/72>.
3. Add a comment with the contents of `amf0-help/ISSUE.md`.
4. If attaching files, attach only the minimal set above or link a small gist.
5. End with the PR offer already included in the comment.
6. If maintainers prefer a PR, fork the repo, add regression tests first, then patch writer/reference-cache behavior.

## If a new issue is required

Use this title:

```text
Amf0Writer counts primitive values when assigning AMF0 reference indices
```

Use the same `ISSUE.md` body, but remove the first "Recommended use" paragraph that points to `#72`.
