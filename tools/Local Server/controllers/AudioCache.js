const { Howl } = require('howler');
const { JSDOM } = require('jsdom');
const webAudioAPI = require('node-web-audio-api');

// 浏览器环境模拟
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.window = dom.window;
global.document = dom.window.document;
global.navigator = {
    userAgent: 'node.js',
    platform: 'Node'
};
global.AudioContext = webAudioAPI.AudioContext;
global.WebAudioContext = webAudioAPI.WebAudioContext;

// 模拟 localStorage
global.localStorage = {
    getItem: () => null,
    setItem: () => {}
};

// 模拟 window 和 document 的事件监听方法
global.window.addEventListener = () => {};
global.document.addEventListener = () => {};
global.document.removeEventListener = () => {};

class AudioCache {
    constructor() {
        this.cache = {};
        this.maxAge = 60000;
        this.unloadQueue = new Set();
    }

    getOrCreate(src, options = {}) {
        if (!src) throw new Error('Source is required for getOrCreate');

        if (this.cache[src]) {
            this.cache[src].lastAccess = Date.now();
            return this.cache[src].instance;
        }

        const instance = new Howl({
            src: [src],
            volume: options.volume !== undefined ? options.volume : 1.0,
            loop: options.loop || false,
            onloaderror: (id, error) => {
                console.error(`Error loading audio source ${src}:`, error);
                delete this.cache[src];
            },
            onplayerror: (id, error) => {
                console.error(`Error playing audio source ${src}:`, error);
                instance.once('unlock', () => instance.play());
            }
        });

        this.cache[src] = {
            instance: instance,
            lastAccess: Date.now(),
        };

        return instance;
    }

    cleanUp() {
        const now = Date.now();
        for (const src in this.cache) {
            if (now - this.cache[src].lastAccess > this.maxAge) {
                this.remove(src);
            }
        }
    }

    remove(src) {
        if (!src || !this.cache[src]) return;

        const instance = this.cache[src].instance;
        if (instance && typeof instance.unload === 'function') {
            if (!instance.playing()) {
                try {
                    instance.unload();
                    console.log(`Successfully unloaded audio instance for ${src}`);
                } catch (error) {
                    console.error(`Error unloading instance for ${src}:`, error);
                }
            } else {
                this.unloadQueue.add(src);
                instance.once('end', () => {
                    this.unloadQueue.delete(src);
                    this.remove(src);
                });
                instance.once('pause', () => {
                    this.unloadQueue.delete(src);
                    this.remove(src);
                });
            }
        }

        delete this.cache[src];
    }

    get(src) {
        return this.cache[src] ? this.cache[src].instance : null;
    }
}

module.exports = new AudioCache();
