/* Runs inside an opaque sandbox. Only fixed local movie assets and player controls are allowed. */
(function() {
    'use strict';
    var CHANNEL = 'bookshelf-original.v1', session = location.hash.slice(1), player;
    var parentOrigin = new URL(location.href).origin;
    var assets = location.hostname === 'overlay.local' ? 'https://cfn-assets.local/'
        : /^(127\.0\.0\.1|localhost)$/.test(location.hostname) ? parentOrigin + '/flashswf/' : '';
    function report(state) { parent.postMessage({channel:CHANNEL, session:session, state:state}, parentOrigin); }
    if (parent === window || !/^[0-9a-f-]{36}$/.test(session) || !assets) return;
    window.RufflePlayer = {config:{autoplay:'on', unmuteOverlay:'hidden', contextMenu:'off',
        allowScriptAccess:false, allowNetworking:'none', openUrlMode:'deny',
        scale:'showAll', forceScale:true, letterbox:'on', logLevel:'warn',
        publicPath:assets + '_ruffle/'}};
    window.addEventListener('message', function(event) {
        var data = event.data;
        if (event.source !== parent || event.origin !== parentOrigin || !player
                || !data || data.channel !== CHANNEL || data.session !== session) return;
        if (data.action === 'pause') { player.pause(); report('paused'); }
        else if (data.action === 'play') { player.play(); report('playing'); }
    });
    var script = document.createElement('script'); script.src = assets + '_ruffle/ruffle.js';
    script.onerror = function() { report('error'); };
    script.onload = async function() {
        try {
            player = window.RufflePlayer.newest().createPlayer();
            document.getElementById('stage').replaceChildren(player);
            await player.load({url:assets + 'originals/crazy-flasher-1.swf'});
            report('playing');
        } catch (error) { report('error'); }
    };
    document.head.appendChild(script);
})();
