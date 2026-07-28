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

The verifier does not use the JSON file list as its traversal seed. It starts
from the actual `DOMDocument.xml` stage placement, resolves `玩家信息界面`,
selects only the actually placed HP/MP roots, and recursively follows every
descendant `DOMSymbolInstance` over all authored frames. It then:

- compares the independently reconstructed 16-file and 10/5/2 symbol sets;
- reconstructs 17 authored definition edges, expands them to 18 runtime-path
  edges, and compares every scope, matrix, pivot and filter;
- reconstructs 14 timeline summaries and counts `BitmapFill` from that closure;
- reads canonical bytes with `git cat-file`, binds the checkout through
  `git hash-object --path`, separately binds the index to `HEAD`, and
  recomputes the canonical closure digest;
- parses the main RSL import and placement at both `HEAD` and the anchor commit;
- checks the frame41/frame42 includes, display formulas, three runtime animation
  edges, source Git blobs, anchor metadata, and child/main/asLoader identities.

`rawWorktreeBytes` and `rawWorktreeSha256` are diagnostic only. They record the
review machine's Windows checkout and may drift with EOL materialization; the
verifier reports that drift but never lets it control the canonical digest.

Observed result for evidence revision `b0-01a-r3`:

```text
B0-01A verifier OK
revision=b0-01a-r3; files=16; hp=10; mp=5; shared=2; placements=17/18; timelines=14; BitmapFill=0; DOMBitmapInstance=0
canonicalDigest=6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368; cleanFilterBindings=16/16; anchorBlobMatches=16/16
indexBindings=closure16+source6+binaries3; sourceBinary=childSame:true,mainSame:false,asLoaderSame:false; mainImport=head+anchor; sourceLinks=6/6; scriptSemantics=5/5; rawDiagnosticDrift=0
status=placement_closure_frozen; oracleFrozen=false
```

The remaining fail-closed items are the TestLoader/player/process-load binding,
fixed-state raw captures and crop hashes, Flash render-quality identity, and
human confirmation listed in `source-binary-chain.json`. Until those exist,
the strongest permitted conclusion remains `placement_closure_frozen`.
