/* Fixed, isolated document. The Host owns its closed local resource set and CSP. */
(function() {
    'use strict';
    var CHANNEL = 'bookshelf-original.v1', ORIGIN = 'https://cf7-originals.local';
    var parentOrigin = 'https://overlay.local', session = location.hash.slice(1), player;
    function report(state) { parent.postMessage({channel:CHANNEL, session:session, state:state}, parentOrigin); }
    if (parent === window || location.origin !== ORIGIN || !/^[0-9a-f-]{36}$/.test(session)) return;
    window.RufflePlayer = {config:{autoplay:'on', unmuteOverlay:'hidden', splashScreen:false, contextMenu:'on',
        allowScriptAccess:false, allowNetworking:'internal', openUrlMode:'deny', showSwfDownload:false,
        scale:'showAll', forceScale:true, letterbox:'on', logLevel:'warn',
        deviceFontRenderer:'canvas', backgroundExecutionMode:'none', publicPath:ORIGIN + '/ruffle/'}};
    window.addEventListener('message', function(event) {
        var data = event.data;
        if (event.source !== parent || event.origin !== parentOrigin || !player
                || !data || data.channel !== CHANNEL || data.session !== session) return;
        if (data.action === 'pause') { player.ruffle().suspend(); report('paused'); }
        else if (data.action === 'play') { player.ruffle().resume(); report('playing'); }
    });
    async function load() {
        try {
            var response = await fetch('/session/' + session + '/manifest.json', {cache:'no-store'});
            if (!response.ok) throw new Error('content_unavailable');
            var info = await response.json(), chapter = info.chapter, language = info.language;
            if (!Number.isInteger(chapter) || chapter < 1 || chapter > 6 || !['cn','en'].includes(language)
                    || (chapter === 1 && language !== 'cn') || info.swfFileName !== 'cf' + chapter + '-' + language + '.swf'
                    || info.movieUrl !== ORIGIN + '/session/' + session + '/movie.swf'
                    || info.baseUrl !== ORIGIN + '/session/' + session + '/exes/') throw new Error('invalid_content');
            var movie = await fetch(info.movieUrl, {cache:'no-store'});
            if (!movie.ok) throw new Error('content_unavailable');
            var data = await movie.arrayBuffer();
            if (data.byteLength < 8 || data.byteLength > 24 * 1024 * 1024) throw new Error('invalid_content');
            var script = document.createElement('script'); script.src = ORIGIN + '/ruffle/ruffle.js';
            await new Promise(function(resolve, reject) { script.onload = resolve; script.onerror = reject; document.head.appendChild(script); });
            player = window.RufflePlayer.newest().createPlayer();
            document.getElementById('stage').replaceChildren(player);
            await player.ruffle().load({data:data, swfFileName:info.swfFileName, base:info.baseUrl});
            report('playing');
        } catch (error) { report('error'); }
    }
    load();
})();
