// ============================================================================
// 子弹队列管理器（轻量版）
// ----------------------------------------------------------------------------
// 功能：管理子弹队列并提供有序访问，优化碰撞检测缓存命中率
// ============================================================================

import org.flashNight.naki.Sort.*;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue {
    
    private var bullets:Array;
    private var needsSort:Boolean;
    
    /**
     * 构造函数
     */
    public function BulletQueue() {
        this.bullets = [];
        this.needsSort = false;
    }
    
    /**
     * 添加子弹到队列
     */
    public function add(bullet:MovieClip):Void {
        if (bullet && bullet.aabbCollider) {
            this.bullets.push(bullet);
            this.needsSort = true;
        }
    }
    
    /**
     * 按左边界排序子弹
     */
    public function sortByLeftBoundary():Void {
        if (!this.needsSort || this.bullets.length <= 1) {
            return;
        }
        
        var self = this;
        PDQSort.sort(this.bullets, function(a:MovieClip, b:MovieClip):Number {
            var leftA:Number = a.aabbCollider.left;
            var leftB:Number = b.aabbCollider.left;
            return leftA < leftB ? -1 : (leftA > leftB ? 1 : 0);
        });
        
        this.needsSort = false;
    }
    
    /**
     * 获取排序后的子弹数组
     */
    public function getSortedBullets():Array {
        this.sortByLeftBoundary();
        return this.bullets;
    }
    
    /**
     * 清空队列
     */
    public function clear():Void {
        this.bullets = [];
        this.needsSort = false;
    }
    
    /**
     * 移除已销毁的子弹
     */
    public function removeDestroyed():Void {
        var activeBullets:Array = [];
        for (var i:Number = 0; i < this.bullets.length; i++) {
            var bullet:MovieClip = this.bullets[i];
            if (bullet && bullet._parent && !bullet.shouldDestroy) {
                activeBullets.push(bullet);
            }
        }
        this.bullets = activeBullets;
    }
    
    /**
     * 获取子弹数量
     */
    public function getCount():Number {
        return this.bullets.length;
    }
}