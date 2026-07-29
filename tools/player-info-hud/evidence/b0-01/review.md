# B0-01A placement closure review

This directory contains repository-only evidence. It freezes the exact HP/MP
placement closure and its Git/source-binary ancestry; it does not contain a
Flash capture and therefore does not establish `oracle_frozen`.

## Read-only independent verifier

Run from the repository root in Windows PowerShell:

```powershell
chcp.com 65001 | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File tools/player-info-hud/evidence/b0-01/verify-b0-01a.ps1
```

The verifier does not use the JSON file list as its traversal seed. It resolves
the linkage-exported `玩家信息界面` symbol, selects only its HP/MP roots, and
recursively follows every descendant `DOMSymbolInstance` over all authored
frames. It separately reads the child `DOMDocument.xml` placement so that the
standalone document wrapper is never confused with the symbol imported by the
main RSL. It then:

- compares the independently reconstructed 16-file and 10/5/2 symbol sets;
- reconstructs 17 authored definition edges, expands them to 18 runtime-path
  edges, and compares every scope, matrix, pivot and filter;
- reconstructs 14 timeline summaries and counts `BitmapFill` from that closure;
- reads canonical bytes with `git cat-file`, binds the checkout through
  `git hash-object --path`, separately binds the index to `HEAD`, and
  recomputes the canonical closure digest;
- parses the main RSL import and placement at both `HEAD` and the anchor commit;
- proves two distinct placement profiles: directly loading the child document
  adds the wrapper `ty=3` and composes HP/MP to `5.65/-1.3`, while the main RSL
  places the exported symbol at an identity root (`ty=0`) and therefore uses
  the symbol-local HP/MP `ty=2.65/-4.3`;
- checks the frame41/frame42 includes, display formulas, three runtime animation
  edges, source Git blobs, anchor metadata, and child/main/asLoader identities.

`rawWorktreeBytes` and `rawWorktreeSha256` are diagnostic only. They record the
review machine's Windows checkout and may drift with EOL materialization; the
verifier reports that drift but never lets it control the canonical digest.

Observed result for evidence revision `b0-01a-r4`:

```text
B0-01A verifier OK
revision=b0-01a-r4; files=16; hp=10; mp=5; shared=2; placements=17/18; timelines=14; BitmapFill=0; DOMBitmapInstance=0
canonicalDigest=6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368; cleanFilterBindings=16/16; anchorBlobMatches=16/16
indexBindings=closure16+source6+binaries3; sourceBinary=childSame:true,mainSame:false,asLoaderSame:false; mainImport=head+anchor; sourceLinks=6/6; scriptSemantics=5/5; rawDiagnosticDrift=0
placementProfiles=standalone_child_document_wrapper:mainRuntimeEquivalent=false,rootTy=3,hpTy=5.65,mpTy=-1.3;main_rsl_exported_symbol:runtimeTruth=true,rootTy=0,hpTy=2.65,mpTy=-4.3
status=placement_closure_frozen; oracleFrozen=false
```

The seventh-round direct-child TestLoader capture remains honest historical
evidence for `standalone_child_document_wrapper`; it is not equivalent to the
main RSL placement and cannot become the main runtime oracle merely through a
human signature. The remaining fail-closed items are an identity-root exported
symbol (or actual main RSL) capture, its loader/player/process binding,
fixed-state raw captures and crop hashes, Flash render-quality identity, and
human confirmation listed in `source-binary-chain.json`. Until those exist,
the strongest permitted conclusion remains `placement_closure_frozen`.
