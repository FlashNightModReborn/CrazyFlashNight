const { Howl, Howler } = require('howler');

let soundInstance = null;

function handleAudioTask(payload) {
    const { action, src, options = {} } = payload;

    switch (action) {
        case 'play':
            if (!soundInstance) {
                soundInstance = new Howl({
                    src: [src],
                    volume: options.volume || 1.0,
                    loop: options.loop || false,
                });
            }
            soundInstance.play();
            return JSON.stringify({ success: true, message: 'Audio started playing' });

        case 'pause':
            if (soundInstance) {
                soundInstance.pause();
                return JSON.stringify({ success: true, message: 'Audio paused' });
            }
            return JSON.stringify({ success: false, error: 'No audio instance to pause' });

        case 'stop':
            if (soundInstance) {
                soundInstance.stop();
                soundInstance = null; // Clear instance on stop
                return JSON.stringify({ success: true, message: 'Audio stopped' });
            }
            return JSON.stringify({ success: false, error: 'No audio instance to stop' });

        case 'setVolume':
            const volume = options.volume;
            if (volume !== undefined && soundInstance) {
                soundInstance.volume(volume);
                return JSON.stringify({ success: true, message: `Volume set to ${volume}` });
            }
            return JSON.stringify({ success: false, error: 'Invalid volume or no audio instance' });

        default:
            return JSON.stringify({ success: false, error: 'Unknown action' });
    }
}

module.exports = handleAudioTask;
