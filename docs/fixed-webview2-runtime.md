# Fixed WebView2 runtime and input failure containment

The launcher ships Microsoft WebView2 Fixed Version Runtime x64 154.0.4258.53.
`launcher/webview2-runtime.lock.json` binds the official download URL, complete CAB
SHA-256 and size, seven deterministic chunks, and all 257 extracted files.
The managed WebView2 SDK version is separately pinned in Directory.Packages.props.

The producer downloads or verifies the locked CAB, expands it, verifies the full
inventory and Microsoft browser signature, and writes 48 MiB chunks to
`runtime/webview2/`. Those chunks participate in the existing v2 payload closure,
bootstrap manifest, independent builder comparison, and promotion transaction.
This representation avoids GitHub's individual-file size limit without stripping
engine files or excluding them from the release identity. Both builders run the
same verification; changing the dependency changes artifact and producer identities.

Before any production WebView is created, the launcher verifies its shipped
chunks and materializes their complete contents in a content-addressed directory
under `%LOCALAPPDATA%/CF7Launcher/WebView2/Fixed`. It verifies every extracted file
on each process startup, rejects links and unexpected files, and preserves a
corrupt cache by moving it aside. Preparation is serialized between processes.
The initial expansion requires approximately 700 MB of free cache space plus a
temporary CAB copy, and subsequent startup only validates the existing cache.
No network download or system WebView2 installation is required at runtime.

Every production host uses this explicit engine directory and verifies both the
loaded version and actual browser executable path. Environment/policy overrides
that select another engine fail clearly. Windows 10 extraction grants read and
execute access to the two AppContainer groups required by Microsoft; Windows 11
does not need that grant. Missing or corrupt shipped parts are repaired through
game file verification, rather than installing an unrelated system engine.
Each pinned engine version also has its own browser profile subdirectory, so
upgrades and rollbacks leave the other version's profile intact.

The publisher must update the lock and rerun the release train for engine security
updates. Fixed Version does not update itself. Keep the complete Microsoft and
third-party license files contained in the original CAB.

World mouse input is initialized on the overlay's UI message-loop thread before
Web initialization begins. Cursor control requests arriving from the socket read
thread marshal their state updates to that UI thread. User activation queues an
idle Flash focus restore only while the Guardian still owns foreground, has no
panel owner, and has no native control focus to preserve. Every recovery action
rechecks eligibility, so switching to another application cancels it.

A terminal Web failure or absence of document readiness for 20 seconds retires
unposted generic panel intents. Superseding a deferred intent also retires its
old game-side state. Existing `shopPanelClose`, `stageSelectPanelClose`,
`mapPanelClose` and `taskPanelClose` commands provide the matching cleanup;
an already-presented same-name instance is preserved. Tracked writes continue
to use their existing exact-owner reconciliation paths. These changes do not
alter AS2, XFL or SWF assets.

Validation must distinguish pure lifecycle/integrity tests, live WebView/input
tests, candidate entry, promotion, installed entry and the original tester's
physical regression. The tester should check window resizing, clicking NPCs,
movement after switching applications, shop close/unpause, and repeated exits
from the garage. A different machine cannot close that final acceptance point.

References:

- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution
- https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc
- https://developer.microsoft.com/en-us/microsoft-edge/webview2/
