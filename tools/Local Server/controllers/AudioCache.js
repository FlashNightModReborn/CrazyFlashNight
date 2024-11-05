const { Howl } = require('howler');

class AudioCache {
    constructor() {
        this.cache = {}; // 存储音频实例
        this.maxAge = 60000; // 设置最大空闲时间，单位毫秒
        this.unloadQueue = new Set(); // 队列中等待卸载的实例
    }

    getOrCreate(src, options = {}) {
        if (!src) {
            throw new Error('Source is required for getOrCreate');
        }

        if (this.cache[src]) {
            // 更新最后访问时间
            this.cache[src].lastAccess = Date.now();
            return this.cache[src].instance;
        }

        // 创建新的音频实例并缓存
        const instance = new Howl({
            src: [src],
            volume: options.volume !== undefined ? options.volume : 1.0,
            loop: options.loop || false,
            onloaderror: (id, error) => {
                console.error(`Error loading audio source ${src}:`, error);
            },
            onplayerror: (id, error) => {
                console.error(`Error playing audio source ${src}:`, error);
                instance.once('unlock', () => {
                    instance.play();
                });
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
                this.remove(src); // 使用 remove 方法来确保资源正确卸载
            }
        }
    }

    remove(src) {
        if (!src || !this.cache[src]) return;

        const instance = this.cache[src].instance;
        if (instance && typeof instance.unload === 'function') {
            if (!instance.playing()) {
                try {
                    instance.unload(); // 卸载音频实例
                    console.log(`Successfully unloaded audio instance for ${src}`);
                } catch (error) {
                    console.error(`Error unloading instance for ${src}:`, error);
                }
            } else {
                console.warn(`Attempted to remove instance for ${src} while still playing. Adding to unload queue.`);
                this.unloadQueue.add(src);
                // 监听音频结束事件，自动卸载
                instance.once('end', () => {
                    this.unloadQueue.delete(src);
                    this.remove(src); // 尝试再次卸载
                });
                // 监听 pause 事件，如果音频被暂停，则尝试卸载
                instance.once('pause', () => {
                    this.unloadQueue.delete(src);
                    this.remove(src); // 尝试再次卸载
                });
            }
        }

        delete this.cache[src]; // 从缓存中删除
    }

    get(src) {
        return this.cache[src] ? this.cache[src].instance : null;
    }
}

module.exports = new AudioCache(); // 导出单例
