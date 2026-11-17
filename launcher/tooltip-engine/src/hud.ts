namespace TooltipEngine {
    function finite(value: any): number { const n = as2Number(value); return Number.isFinite(n) ? n : 0; }
    function text(value: any): string { return value == null ? '' : String(value); }
    function percent(current: any, maximum: any): string {
        return Number(maximum) > 0 ? Math.floor(Number(current) / Number(maximum) * 100) + '%' : '未就绪';
    }
    /** Presentation of already-authorized HUD snapshots; no resource availability recomputation. */
    export function buildHudResult(input: TooltipInput): TooltipResult {
        const data = input.data;
        if (!data || typeof data !== 'object' || Array.isArray(data)) throw new InputError('invalid_hud_input');
        let html = '', profile = 'dense';
        let document: TooltipDocument;
        switch (input.mode) {
            case 'action': {
                html = 'Lee 固定招式。按 ' + text(data.keyLabel) + ' 发动；不消耗 MP。';
                const desc = text(data.description);
                document = NativeTooltipDocument.buildSkill(text(data.name), html, desc);
                return { document, introHTML: html, descHTML: desc, details: plainText(html + desc).substr(0, 4096) };
            }
            case 'weapon':
                html = '<B>' + text(data.name) + '</B><BR>冷却：' + finite(data.cooldown) / 1000 + ' 秒';
                html += '<BR>MP消耗：' + finite(data.mp);
                if (finite(data.hp) > 0) html += '<BR>生命消耗：' + finite(data.hp);
                if (finite(data.sp) > 0) html += '<BR>技能点消耗：' + finite(data.sp);
                if (text(data.description)) html += '<BR>' + text(data.description);
                if (text(data.information)) html += '<BR>' + text(data.information);
                html += resourceHintHtml(input.resourceHint || data.resourceHint);
                break;
            case 'switch':
                profile = 'simple';
                html = '<B>药剂组 ' + (data.bank === 0 ? 'I' : 'II') + '</B><BR>点击或按 ' + data.switchKey + ' 切换另一组药剂。';
                html += '<BR>同一列共用冷却，换组不会重置冷却。';
                if (!data.otherBankHasStock) html += "<BR><FONT COLOR='#e87864'>另一组没有剩余药剂，暂时无法切换。</FONT>";
                break;
            case 'resources':
                if (!Array.isArray(data.hp) || !Array.isArray(data.mp) || !Array.isArray(data.shield) || !Array.isArray(data.experience)) throw new InputError('invalid_vitals');
                html = '生命：' + Math.floor(data.hp[0]) + ' / ' + Math.floor(data.hp[1]) + '（' + percent(data.hp[0], data.hp[1]) + '）';
                html += '<BR>护盾：' + (!data.shieldReady ? '未就绪' : data.shieldPresent ? Math.floor(data.shield[0]) + ' / ' + Math.floor(data.shield[1]) : '无护盾');
                html += data.mp[0] === 0 && data.mp[1] === 0 ? '<BR>MP：本单位不使用此资源。'
                    : '<BR>MP：' + Math.floor(data.mp[0]) + ' / ' + Math.floor(data.mp[1]) + '（' + percent(data.mp[0], data.mp[1]) + '）';
                html += '<BR>韧性：' + Math.floor(data.poise * 100) + '%<BR>经验：' + Math.floor(data.experience[0]) + ' / ' + Math.floor(data.experience[2]);
                html += '<BR>技能点：' + Math.floor(data.sp);
                break;
            default: throw new InputError('invalid_hud_mode');
        }
        document = NativeTooltipDocument.buildBody(html, profile);
        return { document, introHTML: '', descHTML: html, details: plainText(html).substr(0, 4096) };
    }
}
