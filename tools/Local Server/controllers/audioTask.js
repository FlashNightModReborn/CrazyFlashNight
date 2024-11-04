const audioCache = require('./AudioCache'); // 引入 AudioCache

function handleAudioTask(payload) {
    const { action, src, options = {} } = payload;

    switch (action) {
        case 'play':
            const instance = audioCache.getOrCreate(src, options);
            instance.play();
            return JSON.stringify({ success: true, message: 'Audio started playing' });

        case 'pause':
            const pauseInstance = audioCache.get(src);
            if (pauseInstance) {
                pauseInstance.pause();
                return JSON.stringify({ success: true, message: 'Audio paused' });
            }
            return JSON.stringify({ success: false, error: 'No audio instance to pause' });

        case 'stop':
            const stopInstance = audioCache.get(src);
            if (stopInstance) {
                stopInstance.stop();
                audioCache.remove(src); // 从缓存中移除
                return JSON.stringify({ success: true, message: 'Audio stopped' });
            }
            return JSON.stringify({ success: false, error: 'No audio instance to stop' });

        case 'setVolume':
            const volume = options.volume;
            const volumeInstance = audioCache.get(src);
            if (volume !== undefined && volumeInstance) {
                volumeInstance.volume(volume);
                return JSON.stringify({ success: true, message: `Volume set to ${volume}` });
            }
            return JSON.stringify({ success: false, error: 'Invalid volume or no audio instance' });

        default:
            return JSON.stringify({ success: false, error: 'Unknown action' });
    }
}

module.exports = handleAudioTask;
