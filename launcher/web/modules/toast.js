/**
 * Toast module - 面板 toast 桥接（NativeHud 承载渲染）。
 *
 * 常驻 web toast DOM 已随 useNativeHud=false 分支拆除：add() 不再写 DOM，
 * 改为把原始 Flash htmlText 子集经 Bridge.send 上送 Host（type:'panel-toast'），
 * 由 WebOverlayForm 路由到 IToastSink → NativeHud ToastWidget 渲染。
 * 白名单语义保留：原生侧 FlashHtmlParser 同样只认 <font color="..."> 与 <BR>，
 * 其余标签剥离；这里上送原始子集而非 DOM 转换结果。
 *
 * severity 音效契约不变：'success'/'error' 分别播 BootstrapAudio.cue('success')/cue('rejected')，
 * 缺省静默（契约 §6）。已有显式结果音的路径不要传 severity，避免双响。
 */
var Toast = (function() {
    'use strict';

    function add(rawHtml, severity) {
        // severity 结果音挂钩：'success'/'error' → success/rejected；其他/缺省静默
        if (severity === 'success' || severity === 'error') {
            var A = window.BootstrapAudio;
            if (A && typeof A.cue === 'function') {
                A.cue(severity === 'success' ? 'success' : 'rejected');
            }
        }
        if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.send === 'function') {
            Bridge.send({
                type: 'panel-toast',
                html: rawHtml == null ? '' : String(rawHtml),
                severity: severity || null
            });
        }
    }

    return { add: add };
})();
