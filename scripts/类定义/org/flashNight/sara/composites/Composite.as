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

import org.flashNight.sara.DynamicsEngine;
import org.flashNight.sara.util.*;

class org.flashNight.sara.composites.Composite {
	
	public var centerX:Number;
	public var centerY:Number; // 中心点坐标
	public var rotation:Number;

	private var dmc:MovieClip;
	private var isVisible:Boolean;
	
	public function Composite (posX:Number, posY:Number, angle:Number) 
	{
		centerX = posX;
		centerY = posY;
		rotation = angle;

		isVisible = false; // 设置素材才启用
	}

	public function dispose(e:DynamicsEngine):Void {
		// Remove the MovieClip to free graphical resources
		if (dmc) {
			dmc.removeMovieClip();
			dmc = null;
		}

		// Reset visibility
		isVisible = false;

		// Reset center coordinates and rotation
		centerX = 0;
		centerY = 0;
		rotation = 0;

		e.removeComposite(this);
	}

	public function createContainer(linkageId:String, parent:MovieClip):MovieClip
	{
		dmc = MovieClipUtils.createLinkedClip(linkageId, parent);
		return dmc;
	}


	public function setContainer(container:MovieClip):Void {
		dmc = container;
		isVisible = true;
	}

	public function getContainer():MovieClip {	
		return dmc;
	}

	public function removeContainer():Void {
		dmc.removeMovieClip();
	}

	public function setVisible(visible:Boolean):Void {
		isVisible = visible;
	}

	public function paint():Void
	{
		dmc._x = centerX;
		dmc._y = centerY;
		dmc._rotation = rotation;
	}

	// 接口
	public function synchronize():Void
	{
		//_root.服务器.发布服务器消息(centerX + "," + centerY + "," + rotation);
	}

	private function setDmcPos(newX:Number, newY:Number):Void
	{
		dmc._x = newX;
		dmc._y = newY;
	}

	private function setDmcRotation(newAngle:Number):Void
	{
		dmc._rotation = newAngle;
	}

	public function moveTo(newX:Number, newY:Number):Void 
	{
		centerX = newX;
		centerY = newY;
	}


	public function translate(dx:Number, dy:Number):Void 
	{
		centerX += dx;
		centerY += dy;
	}

	public function rotate(angle:Number, centerX:Number, centerY:Number):Void 
	{
		// 如果没有指定旋转中心，那么默认以对象当前中心进行旋转
		if (isNaN(centerX) || isNaN(centerY)) {
			// 只更新旋转角度
			this.rotation += angle;
		} else {
			// 计算对象当前中心到指定旋转中心的位移
			var dx:Number = this.centerX - centerX;
			var dy:Number = this.centerY - centerY;

			// 使用旋转矩阵计算新的位置
			var radianAngle:Number = angle * Math.PI / 180;
			var cosAngle:Number = Math.cos(radianAngle);
			var sinAngle:Number = Math.sin(radianAngle);

			// 根据提供的旋转中心计算新的中心位置
			var newX:Number = cosAngle * dx + sinAngle * dy + centerX;
			var newY:Number = -sinAngle * dx + cosAngle * dy + centerY;

			// 更新对象的中心位置
			this.centerX = newX;
			this.centerY = newY;
		}
	}
}