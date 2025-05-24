# AS2 类 *EventPool*

## 描述

一个可以在不同分区中寄存事件（即函数），并可以指定分区，执行其中所有事件的容器类。

用于跨系统的事件沟通。

## 构造函数

### `function EventPool()`

初始化创建的EventPool对象。

## 方法

### `function Insert(事件分区: String, 事件: Function): Number`

*事件分区*
String类型。为添加的事件指定分区。

*事件*
本次要添加的事件。具体内容参见本文档 **事件** 栏。

*返回值*
该事件在EventPool内部事件池内的索引。

该方法向指定的分区内添加事件，待以后执行。返回的事件索引不区分事件分区，是该事件未被执行之前，在该EventPool中的唯一索引。

### `function Exec(事件分区: String, 指定参数: Object): Void`

*事件分区*
String类型。指定本次将要执行全部事件的分区。

*指定参数*
服从下文中 *function AddArgs(args: Object): Void* 方法中 *args* 参数的格式。除了通过AddArg()和AddArgs()所添加的参数之外，若想在此次执行中额外添加变量，则应使用本参数进行传递。

执行指定分区内现有的全部事件，并清空此分区。

### `function AddArg(参数名: String, 参数值: Object): Void`

*参数名*
要向该EventPool内添加的参数的名称。

*参数值*
要向该EventPool内添加的参数的值。注意，如果传入的参数类型为Array或Object，则传入的是对原对象的引用。

添加参数。该参数能在本EventPool所有的事件执行中以this.xxx的方式调用。

### `function AddArgs(args: Array): Void`

*args*
要向该EventPool内添加的参数的数组。

添加参数，args的格式为[["参数名1", xxx], ["参数名2", yyy], ...]，效果同AddArg("参数名1", xxx); AddArg("参数名2", yyy); ...

### `function AddArgs(args: Object): Void`

*args*
要向该EventPool内添加的参数的索引数组。

添加参数，args的格式为{ 参数名1: xxx, 参数名2: yyy, ... }，效果同AddArg("参数名1", xxx); AddArg("参数名2", yyy); ...

## 事件

通过Insert()，在特定事件分区内，加入的指定函数，即被称作“事件”。在事件的函数体定义内，AS2允许了一些特殊功能的使用。

### this

在事件的函数体定义内，this将指向该EventPool在运行时构造的一个特殊Object，用户可以通过this访问传递给EventPool，或本次Exec()调用时传入的额外参数。具体情况见示例1.

#### 示例1

~~~TypeScript

var evts = new EventPool();
evts.AddArg("这是一个参数", 12);
evts.Insert("参数", function ()
{
    trace(this.这是一个参数);
});
evts.Exec("参数");          // 输出：12

~~~

### this._parent

为了防止出现非常棘手的情况，我们将EventPool本身作为_parent属性放入了this中，一般通过指定EventPool的Constants属性，就可以解决绝大部分的问题。

#### 示例2

~~~TypeScript

var evts = new EventPool();
evts.Constants["我操，你妈的，说真的，我一时想不出到底什么情况非得用到Constants，而不能用后面“使用示例”一栏的技巧解决的问题。不过我还是把Constants的设计保留了。说真的，就按照字面意思存一些常量（比如某项数据的硬上限啥的）也挺好的不是吗"] = "111";
evts.Insert("使用Constants", function ()
{
    trace(this._parent.Constants["我操，你妈的，说真的，我一时想不出到底什么情况非得用到Constants，而不能用后面“使用示例”一栏的技巧解决的问题。不过我还是把Constants的设计保留了。说真的，就按照字面意思存一些常量（比如某项数据的硬上限啥的）也挺好的不是吗"]);
});
evts.Exec("使用Constants");          // 输出：111

~~~

## 使用示例

### 普通使用

该类可以在任何地方Insert()和Exec()事件，可以用于实现繁多的跨系统沟通情况。

如：

- 装备A、B、C具有“进入新地图时，执行...”的效果；

- 装备D、E具有“换弹开始时，执行...”的效果；

- 装备F具有“换弹后，执行...”的效果。

那么使用EventPool，我们可以这样实现这些功能（没错，这其实也是我对物品的label系统的构想）：

#### 示例组3

~~~TypeScript

// 游戏文件夹结构：
// resources/scripts/
//              |--- .../装备事件.as
//              |--- .../读取装备数据.as
//              |--- .../装备物品.as
//              |--- .../过图加载.as
//              |--- .../换弹动作.as

~~~

~~~TypeScript

// 装备事件.as

_root.装备事件 = new Object();
_root.装备事件["装备A"] = {
    "进入新地图": function () { /*...*/ }
};
_root.装备事件["装备B"] = {
    "进入新地图": function () { /*...*/ }
};
_root.装备事件["装备C"] = {
    "进入新地图": function () { /*...*/ }
};
_root.装备事件["装备D"] = {
    "换弹开始": function () { /*...*/ }
};
_root.装备事件["装备E"] = {
    "换弹开始": function () { /*...*/ }
};
_root.装备事件["装备F"] = {
    "换弹结束": function () { /*...*/ }
}

~~~

~~~TypeScript

// 读取装备数据.as

//...
for (var itemName in _root.装备事件)
{
    for (var eventName in _root.装备事件[itemName])
    {
        _root.物品属性列表[itemName]["events"][eventName] = _root.装备事件[itemName][eventName];
    }
}
delete _root.装备事件;

_root.游戏事件池 = new EventPool();
//...

~~~

~~~TypeScript

// 装备物品.as

//...
function 装备物品(/*...*/)
{
    //...
    // 此时item为正在被装备的物品的数据
    for (var eventName in item.events)
    {
        _root.游戏事件池.Insert(eventName, item.events[eventName]);
    }
    //...
}
//...

~~~

~~~TypeScript

// 过图加载.as

//...
function 过图(/*...*/)
{
    //...
    // 此时已经加载完数据，进入新地图了
    _root.游戏事件池.Exec("进入新地图");
    //...
}
//...

~~~

~~~TypeScript

// 换弹动作.as

//...
function 换弹(/*...*/)
{
    _root.游戏事件池.Exec("换弹开始");
    // 这里是原来换弹的代码
    _root.游戏事件池.Exec("换弹结束");
}
//...

~~~

这样，我们就能简单地完成多个系统（角色行为、地图加载、装备数据）之间的沟通，并且不需要系统之间进行任何事先的、静态的约定，只需要在特定的时间点，在需要执行的事件分区进行Exec()就可以了。如果需要系统之间相互暴露数据，只要确保在Exec()之前通过AddArg()进行了参数的添加。

### 参数的添加

不是所有时候我们都希望参数以值传递，能够以引用的形式传递也是很重要的。然而，AS2只有Array和Object对象可以通过引用传递，这就使得AddArg()无法通过普通的方法传递任意类型的引用参数。此时我们可以通过闭包，传入一对函数或一个带有属性的对象作为“参数”。见示例4.1和示例4.2. (分别通过传入一对函数、传入带属性的对象实现传递变量引用)

#### 示例4.1

~~~TypeScript

var num: Number = 111;
var str: String = "111";
trace(num);                                // 输出：111
trace(str);                                // 输出：111

var evts = new EventPool();
evts.AddArg("num变量", num);
evts.AddArg("str变量", str);
evts.Insert("值传递", function ()
{
    this.num变量 = 222;
    this.str变量 = "222";
});
evts.Exec("值传递");
trace(num);                                // 输出：111
trace(str);                                // 输出：111

evts.AddArg("set_num", function (val: Number)
{
    num = val;
});
evts.AddArg("get_num", function ()
{
    return num;
});
evts.AddArg("set_str", function (val: String)
{
    str = val;
});
evts.AddArg("get_str", function ()
{
    return str;
});
evts.Insert("引用传递", function ()         // 没有用到两个get_xxx()函数，但它俩在那就是为了表明这个确实可行，懂我意思
{
    this.set_num(222);
    this.set_str("222");
});
evts.Exec("引用传递");
trace(num);                                // 输出：222
trace(str);                                // 输出：222

~~~

#### 示例4.2

~~~TypeScript

var num: Number = 111;
var str: String = "111";
trace(num);                                // 输出：111
trace(str);                                // 输出：111

var evts = new EventPool();
evts.AddArg("num变量", num);
evts.AddArg("str变量", str);
evts.Insert("值传递", function ()
{
    this.num变量 = 222;
    this.str变量 = "222";
});
evts.Exec("值传递");
trace(num);                                // 输出：111
trace(str);                                // 输出：111

var ref = new Object();
ref.addProperty("num",
    function ()
    {
        return num;
    },
    function (val: Number)
    {
        num = val;
    }
);
ref.addProperty("str",
    function ()
    {
        return str;
    },
    function (val: Number)
    {
        str = val;
    }
);
evts.AddArg("引用", ref);
evts.Insert("引用传递", function ()
{
    this.引用.num = 222;
    this.引用.str = "222";
});
evts.Exec("引用传递");
trace(num);                                // 输出：222
trace(str);                                // 输出：222

~~~

### 指定前置事件

我们通常会给出一系列的事件，而这些事件可能在逻辑上相对独立，因此会被划分成不同的事件给到EventPool中。但是尽管逻辑上独立，它们很有可能在数据上具有依赖性和先后性。

虽然说，大致上Exec()会遵从“先Insert()的事件先执行”的原则，但是我们总是希望能够手动指定事件的依赖关系，因为这样有助于写代码时的精神愉悦，以及后续的可维护、可拓展性。那么，我们可以通过在事件中调用this.RequiresExec()指定前置事件的执行。

~~~TypeScript

var evts = new EventPool();
var index: Number = 0;
evts.Insert("依赖指定", function ()
{
    trace("你好，我是最先Insert的事件。按照Exec()的底层原理，我现在最先被执行:)");
    this.RequiresExec(index);
    trace("我是先Insert的事件，但我需要依赖Insert晚于我的一个事件！\n虽然我被Insert的时候，我还不知道它的索引，但是通过闭包，我仍然可以在实际执行的时候调用它！")
});
index = evts.Insert("依赖指定", function ()
{
    trace("我是下面那个大聪明事件依赖的事件，幸亏鸡蛋非常聪明，想到能用闭包的方式把我的索引传递给它，不然就他妈完蛋了。");
});
evts.Exec("依赖指定");

// 输出：
// 你好，我是最先Insert的事件。按照Exec()的底层原理，我现在最先被执行:)
// 我是下面那个大聪明事件依赖的事件，幸亏鸡蛋非常聪明，想到能用闭包的方式把我的索引传递给它，不然就他妈完蛋了。
// 我是先Insert的事件，但我需要依赖Insert晚于我的一个事件！
// 虽然我被Insert的时候，我还不知道它的索引，但是通过闭包，我仍然可以在实际执行的时候调用它！

~~~