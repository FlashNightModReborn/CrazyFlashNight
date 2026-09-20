/* 有界离线夹具。按钮明确启动验证；生产 lazy closure 不加载本文件。 */
(function() {
    'use strict';
    if (!new URLSearchParams(location.search).has('qa')) return;
    var toolbar = document.createElement('aside');
    toolbar.style.cssText = 'position:fixed;left:4px;bottom:4px;z-index:2147483000;pointer-events:auto;background:#fff;color:#111;padding:4px;font:12px sans-serif;max-width:640px';
    toolbar.innerHTML = '<button id="sleep-qa-run">运行睡眠界面检查</button><button id="sleep-qa-open">重新打开夹具</button><output id="sleep-qa-result">等待检查</output>';
    document.body.appendChild(toolbar);
    document.getElementById('sleep-qa-open').onclick = function() { window.__closeFails = false; window.__cycleEnabled = true; window.__open(); };
    var delay = function(ms) { return new Promise(function(resolve) { setTimeout(resolve, ms); }); };
    function check(condition, text) { if (!condition) throw new Error(text); report.push(text); }
    function click(id) { document.getElementById(id).click(); }
    function setTime(value) { var node = document.getElementById('sleep-time'); node.value = value; node.dispatchEvent(new Event('change', {bubbles:true})); }
    function status() { return SleepPanel.debugState(); }
    var report = [];
    var frame = function() { return new Promise(requestAnimationFrame); };
    async function settleMood() {
        var deadline = performance.now() + 6000;
        while (status().moodAnimating) { if (performance.now() > deadline) throw new Error('配色动画未收敛'); await frame(); }
        var panel=document.querySelector('.sleep-panel'); panel.getBoundingClientRect();
        await Promise.all(panel.getAnimations({subtree:true}).map(function(animation) { return animation.finished.catch(function() {}); }));
    }
    function moodSample() {
        var panel = document.querySelector('.sleep-panel'), style = getComputedStyle(panel);
        var action = getComputedStyle(document.getElementById('sleep-confirm'));
        var rgb = function(value) { return value.match(/[0-9.]+/g).slice(0,3).map(Number); };
        return {time:performance.now(),day:Number(style.getPropertyValue('--sleep-day-weight')),bg:rgb(style.backgroundColor),
            actionContrast:SleepRuntime.contrast(rgb(action.color),rgb(action.backgroundColor)),
            sun:Number(getComputedStyle(document.querySelector('.sleep-sun')).opacity),moon:Number(getComputedStyle(document.querySelector('.sleep-moon')).opacity)};
    }
    async function sampleTransition(change) {
        var samples = [moodSample()]; change(); samples.push(moodSample());
        var deadline = performance.now() + 6000;
        while (status().moodAnimating) {
            if (performance.now() > deadline) throw new Error('逐帧采样超时');
            await frame(); samples.push(moodSample());
        }
        await settleMood(); return samples;
    }
    async function open() { await window.__open(); await delay(30); check(status().phase === 'editing', '床铺快照已载入'); }
    document.getElementById('sleep-qa-run').onclick = async function() {
        var runner = this; runner.disabled = true;
        var output = document.getElementById('sleep-qa-result'); report = []; output.textContent = '检查中…';
        try {
            window.__closeFails = false; window.__cycleEnabled = true; window.__cyclePaused = false; window.__fault = null;
            await open();
            var original = window.__time, writes = window.__commits;
            var root = document.querySelector('.sleep-panel').getBoundingClientRect(), confirm = document.getElementById('sleep-confirm').getBoundingClientRect();
            check(root.left >= -1 && root.top >= -1 && root.right <= innerWidth + 1 && root.bottom <= innerHeight + 1, '面板在当前画布内');
            check(document.elementFromPoint(confirm.x + confirm.width / 2, confirm.y + confirm.height / 2).id === 'sleep-confirm', '入睡按钮可命中');
            check(document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight, '无页面滚动溢出');
            setTime('17:00'); await settleMood();
            var dayColor = getComputedStyle(document.querySelector('.sleep-panel')).backgroundColor;
            setTime('18:15'); await settleMood();
            var middleStyle = getComputedStyle(document.querySelector('.sleep-panel'));
            var middleColor = middleStyle.backgroundColor;
            var parseColor = function(value) { return value.match(/[0-9.]+/g).slice(0,3).map(Number); };
            check(SleepRuntime.contrast(parseColor(middleStyle.color),parseColor(middleColor)) >= 4.5, '暮色中间态文字对比度');
            var actionStyle = getComputedStyle(document.getElementById('sleep-confirm'));
            check(SleepRuntime.contrast(parseColor(actionStyle.color),parseColor(actionStyle.backgroundColor)) >= 4.5
                && document.getElementById('sleep-confirm').textContent === '设好闹钟，入睡', '主按钮有明确文案和可读对比度');
            check(Number(getComputedStyle(document.querySelector('.sleep-sun')).opacity) === 0 && Number(getComputedStyle(document.querySelector('.sleep-moon')).opacity) === 0, '日月过渡无双脸重影');
            setTime('19:30'); await settleMood();
            check(dayColor !== middleColor && middleColor !== getComputedStyle(document.querySelector('.sleep-panel')).backgroundColor, '晨昏包含稳定的中间色调');
            setTime('17:00'); await settleMood();
            var samples = await sampleTransition(function() {
                document.getElementById('sleep-hour-hand').dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true}));
                check(status().draft === 1080 && document.getElementById('sleep-hour-hand').getAttribute('transform') === 'rotate(180 240 225)', '小时吸附与指针即时更新');
            });
            check(samples.length > 10 && samples[0].day === samples[1].day, '小时跳格不让配色同步跳变');
            check(samples.every(function(sample, i) { return !i || Math.abs(sample.day-samples[i-1].day) < .057; }), '逐帧跟随有速度上限');
            check(samples.every(function(sample) { return sample.actionContrast >= 4.5 && !(sample.sun > 0 && sample.moon > 0); }), '过渡途中按钮可读且日月不叠脸');
            setTime('19:30'); await frame(); await frame();
            var beforeReverse = moodSample(); setTime('17:00');
            check(moodSample().day === beforeReverse.day, '快速反向从当前画面续接');
            await settleMood(); check(moodSample().day === 1, '反向后收敛到最新目标');
            setTime('19:30'); await frame(); click('sleep-cancel');
            check(!status().moodAnimating, '关闭时回收配色帧循环');
            await open(); check(moodSample().day === SleepRuntime.visualPhase(360).day, '重开直接呈现当前草稿配色');
            var nativeMatchMedia = window.matchMedia, preference = new EventTarget(); preference.matches = false;
            window.matchMedia = function(query) { return query === '(prefers-reduced-motion: reduce)' ? preference : nativeMatchMedia.call(window,query); };
            try {
                await open(); setTime('19:30'); await frame();
                preference.matches = true; preference.dispatchEvent(new Event('change'));
                check(!status().moodAnimating && moodSample().day === 0, '减少动态偏好事件立即终止帧循环并落到终态');
                setTime('06:00'); check(!status().moodAnimating && moodSample().day === SleepRuntime.visualPhase(360).day, '减少动态偏好下调整时间不启动动画');
                preference.matches = false; preference.dispatchEvent(new Event('change')); setTime('19:30');
                check(status().moodAnimating, '恢复动态偏好后重新平滑追随');
                click('sleep-cancel');
            } finally { window.matchMedia = nativeMatchMedia; }
            await open();
            var missingPaletteStyle = document.createElement('style');
            missingPaletteStyle.textContent = '.sleep-panel{--sleep-day-bg:initial!important;--sleep-day-ink:initial!important;--sleep-night-bg:initial!important}';
            document.head.appendChild(missingPaletteStyle);
            await open();
            setTime('06:00'); await settleMood();
            var missingStyle = getComputedStyle(document.querySelector('.sleep-panel'));
            actionStyle = getComputedStyle(document.getElementById('sleep-confirm'));
            check(SleepRuntime.contrast(parseColor(missingStyle.backgroundColor),[0,0,0]) > 7
                && SleepRuntime.contrast(parseColor(actionStyle.color),parseColor(actionStyle.backgroundColor)) >= 4.5,
                '打开前缺失 CSS 配色属性仍有清晨底色和可读按钮');
            missingPaletteStyle.remove();
            setTime('23:59'); check(status().draft === 1439, '支持精确到分钟');
            document.querySelector('[data-adjust="1"]').click(); check(status().draft === 0, '分钟微调跨午夜');
            click('sleep-halfday'); check(status().draft === 720, '上下午切换相差十二小时');
            document.querySelector('[data-preset="1140"]').click(); check(status().draft === 1140, '夜晚快捷选择');
            document.querySelector('[data-preset="360"]').click(); check(status().draft === 360, '清晨快捷选择');
            var needle = document.getElementById('sleep-minute-hand');
            needle.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true})); check(status().draft === 361, '键盘一分钟微调');
            setTime('25:99'); check(document.getElementById('sleep-confirm').disabled, '非法时间阻止提交');
            document.querySelector('[data-preset="360"]').click(); check(!document.getElementById('sleep-confirm').disabled, '合法选择解除输入错误');
            check(window.__time === original && window.__commits === writes, '所有草稿操作不写时钟');
            click('sleep-cancel'); check(status().phase === 'closed' && window.__time === original, '取消不修改世界时刻');
            await open(); setTime('06:30'); window.__closeFails = true; click('sleep-confirm'); await delay(650);
            check(window.__time === 390 && window.__commits === writes + 1, '单次入睡提交目标时间');
            check(status().phase === 'applied' && !document.getElementById('sleep-error').hidden, '关闭投递失败保留面板与可见错误');
            window.__closeFails = false; click('sleep-confirm'); check(status().phase === 'closed' && window.__commits === writes + 1, '重试关闭不重放入睡');
            await open(); setTime('19:05'); window.__fault = 'unknown_applied'; click('sleep-confirm'); await delay(40);
            check(status().phase === 'unknown', '未知提交禁止重复写');
            check(document.querySelector('[data-preset="360"]').disabled, '未知期间冻结草稿');
            var queries = window.__queries; click('sleep-confirm'); await delay(650);
            check(window.__queries === queries + 1 && window.__commits === writes + 2 && status().phase === 'closed', '查询旧结果后关闭且不重复提交');
            window.__cycleEnabled = false; await open(); check(document.getElementById('sleep-confirm').disabled, '昼夜关闭时禁用入睡');
            click('sleep-cancel'); window.__cycleEnabled = true; window.__cyclePaused = true; await open();
            check(document.getElementById('sleep-status').textContent.indexOf('冻结') >= 0 && !document.getElementById('sleep-confirm').disabled, '冻结时钟的行为明确');
            window.__cyclePaused = false; click('sleep-cancel'); await open();
            window.__fault = 'late'; setTime('12:15'); click('sleep-confirm'); Panels.close(); await open(); await delay(220);
            check(status().phase === 'editing' && status().draft === 360, '关闭重开后旧回包不污染新草稿');
            output.textContent = '通过 ' + report.length + ' 项 · ' + innerWidth + '×' + innerHeight;
            output.dataset.result = JSON.stringify({ok:true,viewport:[innerWidth,innerHeight],checks:report});
        } catch (error) { output.textContent = '失败：' + error.message; output.dataset.result = JSON.stringify({ok:false,error:error.message,checks:report}); }
        finally { runner.disabled = false; }
    };
})();
