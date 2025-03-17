import org.flashNight.sara.util.*;

/**
 * Sara - Customized Dynamics Engine for FlashNight Game
 * Release based on Flade 0.6 alpha modified for project-specific functionalities
 * Copyright 2004, 2005 Alec Cove
 * Modifications by fs, 2024
 *
 * This file is part of Sara, a customized dynamics engine developed for the FlashNight game project.
 *
 * Sara is free software; you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Sara is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
 * License for more details.
 *
 * You should have received a copy of the GNU General Public License along with Sara; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 * Flash is a registered trademark of Adobe Systems Incorporated.
 */

class org.flashNight.sara.util.Vector implements IVector{

    // 向量的 x 和 y 分量
    public var x:Number;
    public var y:Number;

    /**
     * 构造函数，初始化向量的 x 和 y 分量
     * @param px 初始的 x 分量
     * @param py 初始的 y 分量
     */
    public function Vector(px:Number, py:Number) {
        x = px;
        y = py;
    }

    /**
     * 设置向量的值
     * @param px 新的 x 分量
     * @param py 新的 y 分量
     */
    public function setTo(px:Number, py:Number):Void {
        x = px;
        y = py;
    }

    /**
     * 设置向量的值并返回自身
     * @param px 新的 x 分量
     * @param py 新的 y 分量
     * 
     * @return  当前向量（已修改）
     */
    public function assign(px:Number, py:Number):Vector {
        x = px;
        y = py;
        return this;
    }

    /**
     * 复制另一个向量的值到当前向量
     * @param v 要复制的向量
     */
    public function copy(v:Vector):Void {
        x = v.x;
        y = v.y;
    }

    /**
     * 克隆方法，返回当前向量的副本
     * 该方法会创建一个新的 Vector 实例，其 x 和 y 分量与当前向量相同，
     * 用于避免原位修改带来的潜在副作用，适合在需要保护原始数据的场景中使用。
     * @return 一个新的 Vector 实例，x 和 y 分量与当前向量相同
     */
    public function clone():Vector {
        return new Vector(this.x, this.y);
    }

    /**
     * 坐标系转换方法
     * 将当前向量的局部坐标从源影片剪辑 (sourceClip) 的坐标系转换为目标影片剪辑 (targetClip) 的坐标系。
     * 该方法首先将当前向量的坐标从 sourceClip 的局部坐标转换为全局坐标，然后再将其转换为 targetClip 的局部坐标。
     * 此操作不会修改当前向量，而是返回一个转换后的新向量。
     * @param sourceClip 源影片剪辑，当前向量初始所在的坐标系
     * @param targetClip 目标影片剪辑，要转换到的坐标系
     * @return 一个新的 Vector 实例，表示当前向量在目标影片剪辑中的局部坐标
     */
    public function convertCoordinate(sourceClip:MovieClip, targetClip:MovieClip):Vector {
        // 克隆当前向量，避免原位操作修改
        var convertedVector:Vector = this.clone();
        
        // 将 sourceClip 的局部坐标转换为全局坐标
        sourceClip.localToGlobal(convertedVector);
        
        // 将全局坐标转换为 targetClip 的局部坐标
        targetClip.globalToLocal(convertedVector);
        
        return convertedVector;
    }

    /**
     * 计算向量的点积
     * @param v 另一个向量
     * @return 当前向量和 v 的点积结果
     */
    public function dot(v:Vector):Number {
        return x * v.x + y * v.y;
    }

    /**
     * 计算向量的叉积
     * @param v 另一个向量
     * @return 当前向量和 v 的叉积结果（标量）
     */
    public function cross(v:Vector):Number {
        return x * v.y - y * v.x;
    }

    /**
     * 向当前向量加上另一个向量（原位修改）
     * @param v 要相加的向量
     * @return 当前向量（已修改）
     */
    public function plus(v:Vector):Vector {
        x += v.x;
        y += v.y;
        return this;
    }

    /**
     * 返回当前向量与另一个向量相加后的新向量
     * @param v 要相加的向量
     * @return 一个新的向量，表示当前向量和 v 相加的结果
     */
    public function plusNew(v:Vector):Vector {
        return new Vector(x + v.x, y + v.y);
    }

    /**
     * 向当前向量减去另一个向量（原位修改）
     * @param v 要减去的向量
     * @return 当前向量（已修改）
     */
    public function minus(v:Vector):Vector {
        x -= v.x;
        y -= v.y;
        return this;
    }

    /**
     * 返回当前向量减去另一个向量后的新向量
     * @param v 要减去的向量
     * @return 一个新的向量，表示当前向量减去 v 的结果
     */
    public function minusNew(v:Vector):Vector {
        return new Vector(x - v.x, y - v.y);
    }

    /**
     * 将当前向量乘以一个标量（原位修改）
     * @param s 要乘的标量
     * @return 当前向量（已修改）
     */
    public function mult(s:Number):Vector {
        x *= s;
        y *= s;
        return this;
    }

    /**
     * 返回当前向量乘以一个标量后的新向量
     * @param s 要乘的标量
     * @return 一个新的向量，表示当前向量乘以标量后的结果
     */
    public function multNew(s:Number):Vector {
        return new Vector(x * s, y * s);
    }

    /**
     * 计算两个向量之间的距离
     * @param v 另一个向量
     * @return 当前向量与 v 之间的欧几里得距离
     */
    public function distance(v:Vector):Number {
        var dx:Number = x - v.x;
        var dy:Number = y - v.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    /**
     * 将当前向量归一化，使其模长为 1
     * @return 当前向量（已归一化）
     */
    public function normalize():Vector {
       var mag:Number = Math.sqrt(x * x + y * y);
       if (mag > 0) {
           x /= mag;
           y /= mag;
       }
       return this;
    }

    /**
     * 返回当前向量的模长（长度）
     * @return 向量的模长
     */
    public function magnitude():Number {
        return Math.sqrt(x * x + y * y);
    }

    /**
     * 计算当前向量在另一个向量上的投影
     * @param b 要投影的向量
     * @return 投影后的新向量
     */
    public function project(b:Vector):Vector {
        var adotb:Number = this.dot(b);
        var len:Number = (b.x * b.x + b.y * b.y);
        
        var proj:Vector = new Vector(0, 0);
        proj.x = (adotb / len) * b.x;
        proj.y = (adotb / len) * b.y;
        return proj;
    }

    /**
     * 计算当前向量与另一个向量之间的夹角（弧度）
     * @param v 另一个向量
     * @return 两个向量之间的夹角（弧度）
     */
    public function angleBetween(v:Vector):Number {
        var mag1:Number = this.magnitude();
        var mag2:Number = v.magnitude();
        if (mag1 > 0 && mag2 > 0) {
            return Math.acos(this.dot(v) / (mag1 * mag2));
        } else {
            return 0;
        }
    }

    /**
     * 将当前向量按指定角度旋转（弧度）
     * @param theta 旋转的角度（弧度）
     * @return 旋转后的新向量
     */
    public function rotate(theta:Number):Vector {
        var cosVal:Number = Math.cos(theta);
        var sinVal:Number = Math.sin(theta);
        return new Vector(x * cosVal - y * sinVal, x * sinVal + y * cosVal);
    }

    /**
     * 在当前向量和目标向量之间进行线性插值
     * @param v 目标向量
     * @param t 插值因子，范围 0 <= t <= 1
     * @return 插值后的新向量
     */
    public function lerp(v:Vector, t:Number):Vector {
        return new Vector(x + (v.x - x) * t, y + (v.y - y) * t);
    }

    /**
     * 计算当前向量的法线（垂直向量）
     * @return 当前向量的法线
     */
    public function perpendicular():Vector {
        return new Vector(-y, x); // 二维向量的法线为 (-y, x)
    }

    /**
     * 将当前向量转换为字符串表示
     * @return 字符串表示的当前向量
     */
    public function toString():String {
        return "(" + x + "," + y + ")";
    }


    /**
     * 获取 MovieClip 的位置作为 Vector
     * @param mc 目标 MovieClip
     * @return 一个 Vector 实例，表示 MovieClip 的位置
     */
    public static function getPosition(mc:MovieClip):Vector {
        return new Vector(mc._x, mc._y);
    }

    /**
     * 设置 MovieClip 的位置基于当前 Vector
     * @param mc 目标 MovieClip
     */
    public function setPosition(mc:MovieClip):Void {
        mc._x = this.x;
        mc._y = this.y;
    }

    /**
     * 通过向量平移 MovieClip（原位修改）
     * @param mc 目标 MovieClip
     */
    public function translate(mc:MovieClip):Void {
        mc._x += this.x;
        mc._y += this.y;
    }

    /**
     * 使用速度向量更新 MovieClip 的位置
     * @param mc 目标 MovieClip
     * @param velocity 速度向量
     */
    public static function applyVelocity(mc:MovieClip, velocity:Vector):Void {
        mc._x += velocity.x;
        mc._y += velocity.y;
    }

    /**
     * 根据向量的角度旋转 MovieClip
     * @param mc 目标 MovieClip
     * @param theta 旋转的角度（弧度）
     */
    public static function rotateMovieClip(mc:MovieClip, theta:Number):Void {
        mc._rotation += theta * (180 / Math.PI); // AS2 使用度数
    }

    /**
     * 根据向量的大小缩放 MovieClip
     * @param mc 目标 MovieClip
     * @param scaleX 缩放因子 X 方向
     * @param scaleY 缩放因子 Y 方向
     */
    public static function scaleMovieClip(mc:MovieClip, scaleX:Number, scaleY:Number):Void {
        mc._xscale *= scaleX;
        mc._yscale *= scaleY;
    }

    /**
     * 计算两个 MovieClip 之间的相对向量
     * @param source 源 MovieClip
     * @param target 目标 MovieClip
     * @return 一个 Vector 实例，表示从 source 到 target 的相对向量
     */
    public static function calculateRelativeVector(source:MovieClip, target:MovieClip):Vector {
        return new Vector(target._x - source._x, target._y - source._y);
    }

    /**
     * 检测两个 MovieClip 是否发生碰撞
     * 假设每个 MovieClip 都有一个 radius 属性，用于简化碰撞检测
     * @param mc1 第一个 MovieClip
     * @param mc2 第二个 MovieClip
     * @return 如果两个 MovieClip 碰撞，返回 true，否则返回 false
     */
    public static function collisionWith(mc1:MovieClip, mc2:MovieClip):Boolean {
        var v1:Vector = Vector.getPosition(mc1);
        var v2:Vector = Vector.getPosition(mc2);
        var distance:Number = v1.distance(v2);
        var radius1:Number = (mc1.radius != undefined) ? mc1.radius : 0;
        var radius2:Number = (mc2.radius != undefined) ? mc2.radius : 0;
        return distance < (radius1 + radius2);
    }

    /**
     * 让 MovieClip 朝向目标移动（跟随）
     * @param mc 目标 MovieClip
     * @param target 目标位置 Vector
     * @param speed 移动速度
     */
    public function follow(mc:MovieClip, target:Vector, speed:Number):Void {
        var currentPos:Vector = Vector.getPosition(mc);
        var direction:Vector = target.minusNew(currentPos);
        direction.normalize();
        direction.mult(speed);
        this.copy(direction);
        this.translate(mc);
    }

    /**
     * 获取 MovieClip 的全局位置
     * @param mc 目标 MovieClip
     * @return 一个 Vector 实例，表示 MovieClip 的全局位置
     */
    public static function getGlobalPosition(mc:MovieClip):Vector {
        var globalPoint:Object = {x: 0, y: 0};
        mc.localToGlobal(globalPoint);
        return new Vector(globalPoint.x, globalPoint.y);
    }

    /**
     * 线性插值 (Lerp) 移动 MovieClip
     * @param mc 目标 MovieClip
     * @param target 目标位置 Vector
     * @param t 插值因子，范围 0 <= t <= 1
     */
    public function lerpMove(mc:MovieClip, target:Vector, t:Number):Void {
        var currentPos:Vector = Vector.getPosition(mc);
        var newPos:Vector = currentPos.lerp(target, t);
        newPos.setPosition(mc);
    }

    /**
     * 计算两个 MovieClip 之间的夹角（弧度）
     * @param mc1 第一个 MovieClip
     * @param mc2 第二个 MovieClip
     * @return 两个 MovieClip 之间的夹角（弧度）
     */
    public static function angleBetweenClips(mc1:MovieClip, mc2:MovieClip):Number {
        var v1:Vector = Vector.calculateRelativeVector(mc1, mc2);
        return Math.atan2(v1.y, v1.x); // 返回弧度
    }

    /**
     * 反射当前向量关于一个法线向量
     * @param normal 法线向量（应为单位向量）
     * @return 反射后的新向量
     */
    public function reflect(normal:Vector):Vector {
        var dotProduct:Number = this.dot(normal);
        return this.minusNew(normal.multNew(2 * dotProduct));
    }

    /**
     * 向量限制（限制向量的最大长度）
     * @param max 最大长度
     * @return 当前向量（已限制长度）
     */
    public function limit(max:Number):Vector {
        if (this.magnitude() > max) {
            this.normalize();
            this.mult(max);
        }
        return this;
    }

    /**
     * 检查向量是否为零向量
     * @return 如果向量为零向量，返回 true，否则返回 false
     */
    public function isZero():Boolean {
        return this.x == 0 && this.y == 0;
    }

    /**
     * 更新速度和位置基于加速度
     * 假设向量实例代表加速度
     * 并且有两个附加属性 velocity 和 acceleration
     * @param mc 目标 MovieClip
     */
    public function update(mc:MovieClip):Void {
        if (mc.velocity == undefined) {
            mc.velocity = new Vector(0, 0);
        }
        if (mc.acceleration == undefined) {
            mc.acceleration = new Vector(0, 0);
        }
        // 更新速度
        mc.velocity.plus(mc.acceleration);
        // 更新位置
        Vector.applyVelocity(mc, mc.velocity);
    }

    // =================== End of 新增的方法 ===================

}
