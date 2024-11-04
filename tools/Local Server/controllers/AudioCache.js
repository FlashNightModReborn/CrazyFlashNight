const { Howl } = require('howler');

class AudioCache {
    constructor() {
        this.cache = {}; // 存储音频实例
        this.maxAge = 60000; // 设置最大空闲时间，单位毫秒（这里设为1分钟）
    }

    // 获取或创建音频实例
    getOrCreate(src, options = {}) {
        if (this.cache[src]) {
            // 更新最后访问时间
            this.cache[src].lastAccess = Date.now();
            return this.cache[src].instance;
        }

        // 创建新的音频实例并缓存
        const instance = new Howl({
            src: [src],
            volume: options.volume || 1.0,
            loop: options.loop || false,
        });

        this.cache[src] = {
            instance: instance,
            lastAccess: Date.now(),
        };

        return instance;
    }

    // 清理超出最大空闲时间的音频实例
    cleanUp() {
        const now = Date.now();
        for (const src in this.cache) {
            if (now - this.cache[src].lastAccess > this.maxAge) {
                this.cache[src].instance.unload(); // 卸载音频实例
                delete this.cache[src]; // 从缓存中删除
            }
        }
    }

    // 停止并移除特定音频实例
    remove(src) {
        if (this.cache[src]) {
            this.cache[src].instance.unload(); // 卸载音频实例
            delete this.cache[src];
        }
    }

    // 手动获取音频实例（用于暂停、设置音量等操作）
    get(src) {
        return this.cache[src] ? this.cache[src].instance : null;
    }
}

module.exports = new AudioCache(); // 导出单例
