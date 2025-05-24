import org.flashNight.gesh.depth.*;
import org.flashNight.naki.DataStructures.*;

import org.flashNight.neur.Event.*;
import org.flashNight.aven.Coordinator.*;

/**
 * @class DepthManager
 * @description 基于 AVL 树的影片剪辑深度管理器
 *   负责高效管理 MovieClip 的深度排序，支持按需更新与惰性处理
 * @package org.flashNight.gesh.depth
 */
class org.flashNight.gesh.depth.DepthManager {
    /** 关联的父容器 */
    private var container:MovieClip;
    
    /** 基于AVL树的深度排序集合 */
    private var depthTree:TreeSet;
    
    /** 影片剪辑名称到节点的映射表 */
    private var mcNodeMap:Object;
    
    /** 最近一次执行的标记 */
    private var lastProcessed:Number;
    
    /** 脏节点计数器 */
    private var dirtyCount:Number;
    
    /** 是否启用了对相同深度值的处理 */
    private var handleDuplicateDepths:Boolean;
    
    /** 深度管理器的唯一ID（用于调试） */
    private var managerID:String;
    
    /** 深度管理器ID计数器 */
    private static var idCounter:Number = 0;
    
    /**
     * 构造函数
     * @param container 父容器，所有被管理的MovieClip都应是其子级
     * @param handleDuplicateDepths 是否自动处理相同深度值的冲突（默认为true）
     */
    public function DepthManager(container:MovieClip, handleDuplicateDepths:Boolean) {
        this.container = container;
        this.mcNodeMap = {};
        this.lastProcessed = getTimer();
        this.dirtyCount = 0;
        this.managerID = "DM" + (idCounter++);
        
        if (handleDuplicateDepths == undefined) {
            handleDuplicateDepths = true;
        }
        this.handleDuplicateDepths = handleDuplicateDepths;
        
        // 初始化深度树，配置比较函数
        this.depthTree = new TreeSet(createCompareFunction());
        
        // 绑定容器卸载事件，确保正确清理资源
        EventCoordinator.addUnloadCallback(container, this.dispose);
        
        // 记录日志
        trace("[DepthManager] " + this.managerID + " 已创建，关联容器: " + container._name);
    }
    
    /**
     * 创建深度比较函数
     * 比较顺序：
     *   1. 首先按深度值升序排列
     *   2. 当深度值相同时，按时间戳降序排列（后更新的显示在上层）
     * @return 比较函数
     */
    private function createCompareFunction():Function {
        var handleDuplicates:Boolean = this.handleDuplicateDepths;
        
        return function(a:DepthNode, b:DepthNode):Number {
            // 首先按深度值比较
            var depthDiff:Number = a.depth - b.depth;
            
            if (depthDiff != 0) {
                return depthDiff; // 深度不同，返回差值
            }
            
            // 深度相同时的处理逻辑
            if (handleDuplicates) {
                // 时间戳降序，确保后更新的显示在上方
                return b.timestamp - a.timestamp;
            }
            
            // 不处理深度冲突时，保持原有顺序
            return 0;
        };
    }
    
    /**
     * 更新影片剪辑的深度值
     * 主要逻辑：
     *   1. 若节点不存在，则创建并添加到树中
     *   2. 若节点存在但深度改变，则从树中移除并重新插入
     *   3. 标记节点为脏，增加脏节点计数
     *   4. 处理实际深度更新（可能触发AVL树重平衡）
     * 
     * @param mc 要更新深度的影片剪辑
     * @param targetDepth 目标深度值
     * @return 深度是否发生变化
     */
    public function updateDepth(mc:MovieClip, targetDepth:Number):Boolean {
        if (!mc || targetDepth == undefined) {
            trace("[DepthManager] " + this.managerID + " 更新深度失败: 无效参数");
            return false;
        }
        
        var mcName:String = mc._name;
        var node:DepthNode = this.mcNodeMap[mcName];
        var depthChanged:Boolean = false;
        
        // 检查节点是否存在
        if (node == undefined) {
            // 创建新节点并添加到树中
            node = new DepthNode(mc, targetDepth);
            this.mcNodeMap[mcName] = node;
            this.depthTree.add(node);
            this.dirtyCount++;
            
            trace("[DepthManager] " + this.managerID + " 添加新节点: " + mcName + " 深度: " + targetDepth);
            depthChanged = true;
        } else {
            // 更新现有节点
            var oldDepth:Number = node.depth;
            
            // 检查深度是否变化
            if (node.updateDepth(targetDepth)) {
                // 深度发生变化，需要重新排序
                this.depthTree.remove(node);
                this.depthTree.add(node);
                this.dirtyCount++;
                
                trace("[DepthManager] " + this.managerID + " 更新节点: " + mcName + 
                      " 深度从 " + oldDepth + " 变为 " + targetDepth);
                depthChanged = true;
            } else if (this.handleDuplicateDepths) {
                // 深度未变，但更新时间戳以处理相同深度的优先级
                node.setTimestamp(getTimer());
                node.isDirty = true;
                this.dirtyCount++;
                
                // 仅当启用处理重复深度时才需要重新排序
                this.depthTree.remove(node);
                this.depthTree.add(node);
                
                trace("[DepthManager] " + this.managerID + " 更新节点时间戳: " + mcName);
                depthChanged = true;
            }
        }
        
        // 立即处理深度更新
        if (depthChanged) {
            processDepthUpdates();
        }
        
        return depthChanged;
    }
    
    /**
     * 处理所有待更新的深度
     * 该方法执行实际的 swapDepths 操作，应在更新后立即调用
     */
    public function processDepthUpdates():Void {
        if (this.dirtyCount <= 0) {
            return; // 没有待更新的节点
        }
        
        var currentTime:Number = getTimer();
        // 获取排序后的所有节点
        var sortedNodes:Array = this.depthTree.toArray();
        var processedCount:Number = 0;
        
        // 遍历所有节点并应用深度更新
        for (var i:Number = 0; i < sortedNodes.length; i++) {
            var node:DepthNode = sortedNodes[i];
            
            // 只处理脏节点
            if (node.needsUpdate()) {
                // 计算实际使用的深度值
                var actualDepth:Number = node.depth;
                
                // 使用 swapDepths 更新显示深度
                try {
                    node.mc.swapDepths(actualDepth);
                    node.resetDirty();
                    processedCount++;
                } catch (e) {
                    trace("[DepthManager] " + this.managerID + " 深度更新失败: " + 
                          node.mc._name + " 错误: " + e);
                }
            }
        }
        
        // 更新脏节点计数
        this.dirtyCount -= processedCount;
        this.lastProcessed = currentTime;
        
        trace("[DepthManager] " + this.managerID + " 处理了 " + 
              processedCount + " 个深度更新，耗时: " + (getTimer() - currentTime) + "ms");
    }
    
    /**
     * 移除指定影片剪辑的深度管理
     * @param mc 要移除的影片剪辑
     * @return 是否成功移除
     */
    public function removeMovieClip(mc:MovieClip):Boolean {
        if (!mc) return false;
        
        var mcName:String = mc._name;
        var node:DepthNode = this.mcNodeMap[mcName];
        
        if (node != undefined) {
            // 从树中移除节点
            this.depthTree.remove(node);
            delete this.mcNodeMap[mcName];
            
            if (node.needsUpdate()) {
                this.dirtyCount--;
            }
            
            trace("[DepthManager] " + this.managerID + " 已移除节点: " + mcName);
            return true;
        }
        
        return false;
    }
    
    /**
     * 获取指定影片剪辑的当前深度值
     * @param mc 影片剪辑
     * @return 当前深度值，如果未找到则返回 undefined
     */
    public function getDepth(mc:MovieClip):Number {
        if (!mc) return undefined;
        
        var node:DepthNode = this.mcNodeMap[mc._name];
        return node ? node.depth : undefined;
    }
    
    /**
     * 获取当前管理的影片剪辑数量
     * @return 管理的影片剪辑数量
     */
    public function size():Number {
        return this.depthTree.size();
    }
    
    /**
     * 获取当前等待处理的脏节点数量
     * @return 脏节点数量
     */
    public function getDirtyCount():Number {
        return this.dirtyCount;
    }
    
    /**
     * 清空所有深度管理数据
     */
    public function clear():Void {
        // 重置所有数据结构
        this.mcNodeMap = {};
        this.depthTree = new TreeSet(createCompareFunction());
        this.dirtyCount = 0;
        
        trace("[DepthManager] " + this.managerID + " 已清空所有数据");
    }
    
    /**
     * 释放资源并清理引用
     * 当容器被卸载时将自动调用此方法
     */
    public function dispose():Void {
        trace("[DepthManager] " + this.managerID + " 开始销毁...");
        
        // 清理所有引用
        this.clear();
        this.container = null;
        this.depthTree = null;
        this.mcNodeMap = null;
        
        trace("[DepthManager] " + this.managerID + " 已销毁");
    }
    
    /**
     * 获取所有管理的影片剪辑及其深度值的字符串表示
     * 主要用于调试目的
     * @return 描述所有深度关系的字符串
     */
    public function toString():String {
        var result:String = "[DepthManager " + this.managerID + "]\n";
        result += "容器: " + (this.container ? this.container._name : "已销毁") + "\n";
        result += "节点数量: " + this.depthTree.size() + "\n";
        result += "待更新数量: " + this.dirtyCount + "\n";
        
        var nodes:Array = this.depthTree.toArray();
        result += "深度列表:\n";
        
        for (var i:Number = 0; i < nodes.length; i++) {
            var node:DepthNode = nodes[i];
            result += "  " + node.mc._name + " (深度: " + node.depth + 
                     ", 时间戳: " + node.timestamp + 
                     ", 状态: " + (node.isDirty ? "脏" : "清洁") + ")\n";
        }
        
        return result;
    }
}