const audioCache = require('./AudioCache'); // 引入 AudioCache
let currentSources = {}; // 管理多个音频源的状态

function handleAudioTask(payload) {
    let { action, src, options = {} } = payload;

    if (!src) {
        return JSON.stringify({ success: false, error: 'No source provided for action' });
    }

    switch (action) {
        case 'play':
            try {
                const instance = audioCache.getOrCreate(src, options);
                instance.play();
                currentSources[src] = { instance, options, state: 'playing' }; // 更新播放状态
                return JSON.stringify({ success: true, message: `Audio started playing for ${src}` });
            } catch (error) {
                console.error(`Error during play action for ${src}:`, error);
                return JSON.stringify({ success: false, error: `Error playing audio: ${error.message}` });
            }

        case 'pause':
            try {
                const pauseInstance = audioCache.get(src);
                if (pauseInstance && currentSources[src]?.state === 'playing') {
                    pauseInstance.pause();
                    currentSources[src].state = 'paused'; // 更新状态
                    return JSON.stringify({ success: true, message: `Audio paused for ${src}` });
                }
                return JSON.stringify({ success: false, error: `No audio instance to pause or not playing for ${src}` });
            } catch (error) {
                console.error(`Error during pause action for ${src}:`, error);
                return JSON.stringify({ success: false, error: `Error pausing audio: ${error.message}` });
            }

        case 'stop':
            try {
                const stopInstance = audioCache.get(src);
                if (stopInstance && currentSources[src]?.state !== 'stopped') {
                    stopInstance.stop();
                    audioCache.remove(src);
                    delete currentSources[src];
                    return JSON.stringify({ success: true, message: `Audio stopped for ${src}` });
                }
                return JSON.stringify({ success: false, error: `No audio instance to stop for ${src}` });
            } catch (error) {
                console.error(`Error during stop action for ${src}:`, error);
                return JSON.stringify({ success: false, error: `Error stopping audio: ${error.message}` });
            }

        case 'setVolume':
            try {
                const volume = options.volume;
                const volumeInstance = audioCache.get(src);
                if (volume !== undefined && volumeInstance) {
                    volumeInstance.volume(volume);
                    if (currentSources[src]) {
                        currentSources[src].options.volume = volume; // 更新当前音量
                    }
                    return JSON.stringify({ success: true, message: `Volume set to ${volume} for ${src}` });
                }
                return JSON.stringify({ success: false, error: `Invalid volume or no audio instance for ${src}` });
            } catch (error) {
                console.error(`Error during setVolume action for ${src}:`, error);
                return JSON.stringify({ success: false, error: `Error setting volume: ${error.message}` });
            }

        default:
            return JSON.stringify({ success: false, error: 'Unknown action' });
    }
}

module.exports = handleAudioTask;
