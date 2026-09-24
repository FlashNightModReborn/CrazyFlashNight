// This entry MUST NOT import a game class: their DoInitAction precedes frame code.
stop();
Stage.scaleMode = "showAll";
Stage.align = "TL";
_global.__cf7InputIsolationBootstrapV1 = {v:1, mode:"closed-legacy-drivers", module:"C1Island.swf"};
ASSetPropFlags(_global, "__cf7InputIsolationBootstrapV1", 7);
ASSetPropFlags(_global.__cf7InputIsolationBootstrapV1, null, 7);
var island:MovieClip = _root.createEmptyMovieClip("island", 1);
island._lockroot = true;
// The host verifies both SWF hashes before executing this immutable allowlist.
island.loadMovie("C1Island.swf");
