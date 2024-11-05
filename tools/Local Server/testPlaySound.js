const player = require('play-sound')({
    players: ['ffplay', 'mpg123', 'afplay', 'aplay']  // 指定可能的播放器
});

const audioPath = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\resources\\flashswf\\sounds\\soundManager\\LIBRARY\\VOXScrm_Wilhelm scream (ID 0477)_BSB.mp3';

console.log('正在尝试播放音频文件:', audioPath);
console.log('当前播放器配置:', player.players);

player.play(audioPath, (err) => {
    if (err) {
        console.error('播放音频时出错:', err);
        // 输出详细错误信息
        console.log('错误代码:', err.code);
        console.log('错误信号:', err.signal);
        console.log('更多错误信息:', err);
    } else {
        console.log('音频播放完成');
    }
});
