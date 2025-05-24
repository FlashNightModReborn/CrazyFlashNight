const audioCache = require('./AudioCache');
let currentSources = {};

function handleAudioTask(payload) {
    const { action, src, options = {} } = payload;

    if (!src) return JSON.stringify({ success: false, error: 'No source provided for action' });

    try {
        switch (action) {
            case 'play': {
                // 判断是否为 WAV 文件，并使用不同的解码策略
                const instance = audioCache.getOrCreate(src, options);
                if (instance) {
                    instance.play();
                    currentSources[src] = { instance, options, state: 'playing' };
                    return JSON.stringify({ success: true, message: `Audio started playing for ${src}` });
                }
                return JSON.stringify({ success: false, error: `Failed to create audio instance for ${src}` });
            }

            case 'pause': {
                const pauseInstance = audioCache.get(src);
                if (pauseInstance && currentSources[src]?.state === 'playing') {
                    pauseInstance.pause();
                    currentSources[src].state = 'paused';
                    return JSON.stringify({ success: true, message: `Audio paused for ${src}` });
                }
                return JSON.stringify({ success: false, error: `No audio instance to pause or not playing for ${src}` });
            }

            case 'stop': {
                const stopInstance = audioCache.get(src);
                if (stopInstance && currentSources[src]?.state !== 'stopped') {
                    stopInstance.stop();
                    audioCache.remove(src);
                    delete currentSources[src];
                    return JSON.stringify({ success: true, message: `Audio stopped for ${src}` });
                }
                return JSON.stringify({ success: false, error: `No audio instance to stop for ${src}` });
            }

            case 'setVolume': {
                const { volume } = options;
                const volumeInstance = audioCache.get(src);
                if (volume !== undefined && volumeInstance) {
                    volumeInstance.volume(volume);
                    if (currentSources[src]) {
                        currentSources[src].options.volume = volume;
                    }
                    return JSON.stringify({ success: true, message: `Volume set to ${volume} for ${src}` });
                }
                return JSON.stringify({ success: false, error: `Invalid volume or no audio instance for ${src}` });
            }

            default:
                return JSON.stringify({ success: false, error: 'Unknown action' });
        }
    } catch (error) {
        console.error(`Error during ${action} action for ${src}:`, error);
        return JSON.stringify({ success: false, error: `Error performing ${action} action: ${error.message}` });
    }
}

module.exports = handleAudioTask;
