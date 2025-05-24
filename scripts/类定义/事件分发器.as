class 事件分发器
{
/*
事件分发器类 使用说明书

概述

	事件分发器 类是一个灵活的事件处理系统，旨在管理和调度应用程序中的事件。它支持事件捕获和冒泡阶段、优先级管理、条件执行、重复次数，以及阻止事件进一步传播的功能。

功能特点

	事件捕获与冒泡：支持两个不同的事件处理阶段。
	优先级管理：根据优先级执行事件监听器。
	条件执行：只有在满足特定条件时才触发监听器。
	重复次数：指定事件监听器被触发的次数。
	停止传播：允许事件监听器停止事件的进一步传播。

使用方法

	创建实例

	var dispatcher = new 事件分发器();

	添加事件监听器

		通过提供事件名称和监听器对象来添加监听器。监听器对象包括要执行的操作，以及可选的优先级、重复次数和触发条件。


		var listenerId = dispatcher.增加监听器("myEvent", {
			动作: function() { trace("触发了事件！"); },
			动作参数: [],
			优先级: 10,
			重复次数: 5,
			条件: function() { return true; },
			阶段: "冒泡"
		});

	触发事件

		通过指定事件名称来触发事件。可以选择定义事件应该在哪个阶段（捕获或冒泡）触发。


		dispatcher.触发事件("myEvent", "冒泡");

	移除事件监听器

		可以通过唯一ID来移除特定的监听器，或者移除与某事件相关的所有监听器。

		// 通过ID移除特定监听器
		dispatcher.移除监听器("myEvent", listenerId);

		// 移除某个事件的所有监听器
		dispatcher.移除监听器("myEvent", null);

	获取监听器对象

		可以通过其ID获取监听器的详细信息。


		var listenerObject = dispatcher.获取监听器(listenerId);
		trace(listenerObject.动作);

实现细节

	捕获与冒泡：监听器按照阶段（'捕获' 或 '冒泡'）组织。如果未指定阶段，默认为 '冒泡'。
	优先级：优先级数值更高的监听器先执行。默认优先级为 0。
	条件执行：如果条件函数返回 true，则执行监听器。
	重复次数：如果设置为 true，监听器无限次执行。如果是数字，则每触发一次，数值减一，直到减至零时，自动移除监听器。
	阻止传播：如果监听器在执行过程中将 已阻止传播 设置为 true，则不会执行该阶段后续的监听器。
	
*/
	private var 监听器:Object;
	private var 监听器ID:Number = 0;// 用于生成唯一ID
	private var 监听器查找:Object = new Object();// 用于通过ID快速访问监听器对象

	public function 事件分发器()
	{
		this.监听器 = new Object();
	}

	public function 增加监听器(事件:String, 监听器对象:Object):Number
	{
		if (this.监听器[事件] == undefined)
		{
			this.监听器[事件] = {捕获:[], 冒泡:[]};
		}
		var id:Number = this.监听器ID++;
		监听器对象.id = id;

		if (监听器对象.已阻止传播 == undefined)
		{
			监听器对象.已阻止传播 = false;// 默认不阻止传播
		}
		if (监听器对象.阶段 == undefined)
		{
			监听器对象.阶段 = "冒泡";// 默认为冒泡阶段
		}
		if (监听器对象.优先级 == undefined)
		{
			监听器对象.优先级 = 0;// 默认为低优先级
		}
		if (监听器对象.重复次数 === undefined)
		{
			监听器对象.重复次数 = true;// 默认为无限重复
		}
		if (监听器对象.动作参数 === undefined)
		{
			监听器对象.动作参数 = {};// 默认为无限重复
		}
		if (监听器对象.条件 === undefined)
		{
			监听器对象.条件 = function()
			{
				return true;// 默认条件总是返回true
			};
		}

		this.监听器[事件][监听器对象.阶段].push(监听器对象);
		this.监听器查找[id] = 监听器对象;// 存储引用以便快速访问

		// 对监听器数组按优先级进行排序
		this.监听器[事件][监听器对象.阶段].sort(function (a, b)
		{
		return b.优先级 - a.优先级;
		});
		return id;
	}

	public function 获取监听器(监听器ID:Number):Object
	{
		return this.监听器查找[监听器ID];
	}

	public function 移除监听器(事件:String, 监听器ID):Void
	{
		if (监听器ID === null)
		{
			delete this.监听器[事件];// 完全移除这个事件的所有监听器
		}
		else
		{
			var 监听器对象:Object = this.获取监听器(监听器ID);
			if (监听器对象 && this.监听器[事件])
			{
				var 阶段数组:Array = this.监听器[事件][监听器对象.阶段];
				for (var i:Number = 0; i < 阶段数组.length; i++)
				{
					if (阶段数组[i].id == 监听器ID)
					{
						阶段数组.splice(i,1);
						break;
					}
				}
			}
			delete this.监听器查找[监听器ID];// 从查找表中移除
		}
	}

	public function 触发事件(事件:String, 阶段):Void
	{
		if (阶段 === undefined)
		{
			阶段 = "冒泡";
		}

		var 列表:Array = this.监听器[事件] ? this.监听器[事件][阶段] : null;
		if (列表 != undefined)
		{
			var 阻止传播:Boolean = false;
			for (var i:Number = 0; i < 列表.length && !阻止传播; i++)
			{
				var 监听器信息:Object = 列表[i];
				if (监听器信息.条件())
				{
					监听器信息.动作.apply(null,监听器信息.动作参数);
					if (监听器信息.已阻止传播)
					{
						阻止传播 = true;// 确保阻止后续监听器的执行
					}
					if (typeof 监听器信息.重复次数 === "number")
					{
						监听器信息.重复次数 -= 1;
						if (监听器信息.重复次数 <= 0)
						{
							列表.splice(i,1);
							i--;// 调整索引以反映数组已变更
						}
					}
				}
			}
		}

	}
}
/*
var dispatcher = new 事件分发器();
var testId = dispatcher.增加监听器("testEvent", {动作:function ()
{
trace("Test Event Triggered");
}, 动作参数:[]});
dispatcher.触发事件("testEvent");
// 期望输出：Test Event Triggered
dispatcher.增加监听器("testEvent",{动作:function ()
{
trace("High Priority");
}, 优先级:10, 重复次数:2, 动作参数:[]});
dispatcher.触发事件("testEvent");
dispatcher.触发事件("testEvent");
dispatcher.触发事件("testEvent");
// 期望输出：High Priority（两次） Test Event Triggered（三次）
dispatcher.增加监听器("testEvent",{动作:function ()
{
trace("Conditional Event");
}, 条件:function ()
{
return false;
}, 动作参数:[]});
var id = dispatcher.增加监听器("testEvent", {动作:function ()
{
dispatcher.获取监听器(testId).已阻止传播 = true;
trace("Stopping Propagation");
}, 动作参数:[]});
dispatcher.触发事件("testEvent");
// 期望输出：Stopping Propagation
// 不应输出 Conditional Event
dispatcher.移除监听器("testEvent",id);
dispatcher.触发事件("testEvent","冒泡");
// 移除了阻止传播，期望输出：Test Event Triggered
dispatcher.移除监听器("testEvent",null);
dispatcher.触发事件("testEvent","冒泡");
// 不应有输出
*/