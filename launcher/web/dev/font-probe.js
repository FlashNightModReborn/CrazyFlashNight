(async function fontProbe() {
    const fonts = ['Klee One', 'LXGW WenKai Screen', 'Ma Shan Zheng', 'Source Han Serif CN', 'Liu Jian Mao Cao', 'JetBrains Mono'];
    if (document.fonts && document.fonts.ready) await document.fonts.ready;
    await new Promise(r => setTimeout(r, 800));

    console.log('%c=== document.fonts.check (16px) ===', 'color:#0cf;font-weight:bold');
    const checkRows = fonts.map(n => ({
        font: n,
        ok: document.fonts.check('16px "' + n + '"')
    }));
    console.table(checkRows);

    console.log('%c=== fetch cfn-fonts.local ===', 'color:#0cf;font-weight:bold');
    const urls = [
        'https://cfn-fonts.local/klee-one-regular.ttf',
        'https://cfn-fonts.local/lxgw-wenkai-screen.ttf',
        'https://cfn-fonts.local/ma-shan-zheng-regular.ttf',
        'https://cfn-fonts.local/source-han-serif-cn-regular.otf',
        'https://cfn-fonts.local/liu-jian-mao-cao-regular.ttf',
        'https://cfn-fonts.local/jetbrains-mono.woff2'
    ];
    const netRows = [];
    for (const url of urls) {
        try {
            const r = await fetch(url);
            const buf = await r.arrayBuffer();
            const head = Array.from(new Uint8Array(buf.slice(0, 4))).map(b => b.toString(16).padStart(2, '0')).join(' ');
            netRows.push({ url: url.replace('https://cfn-fonts.local/', ''), status: r.status, bytes: buf.byteLength, magic: head });
        } catch (e) {
            netRows.push({ url: url.replace('https://cfn-fonts.local/', ''), status: 'ERR', bytes: 0, magic: e.message });
        }
    }
    console.table(netRows);

    console.log('%c=== rendered diary heading computed (open intel panel first!) ===', 'color:#0cf;font-weight:bold');
    const probes = [
        { sel: '.intel-content[data-skin="diary"] .intel-h5-heading', label: 'diary heading' },
        { sel: '.intel-content[data-skin="diary"] .intel-h5-p', label: 'diary paragraph' },
        { sel: '.intel-content[data-skin="diary"] .intel-h5-note', label: 'diary note' },
        { sel: '.intel-content[data-skin="field-notes"] .intel-h5-heading', label: 'field-notes heading' },
        { sel: '.intel-content[data-skin="dossier"] .intel-h5-heading', label: 'dossier heading' }
    ];
    const compRows = probes.map(p => {
        const el = document.querySelector(p.sel);
        if (!el) return { element: p.label, fontFamily: '(not in current panel)', fontSize: '', weight: '' };
        const cs = getComputedStyle(el);
        return {
            element: p.label,
            fontFamily: cs.fontFamily,
            fontSize: cs.fontSize,
            weight: cs.fontWeight
        };
    });
    console.table(compRows);

    console.log('%c=== @font-face declarations (CSS view) ===', 'color:#0cf;font-weight:bold');
    const faceRows = [];
    for (const f of document.fonts) {
        faceRows.push({ family: f.family, status: f.status, src: (f._urls || '').toString().slice(0, 60) });
    }
    console.table(faceRows);

    console.log('%c=== DONE — copy console output (右键 Console → Save as) and send to Claude ===', 'color:#fc7;font-weight:bold');
})();
