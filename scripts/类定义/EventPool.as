import Allocator;

class EventPool
{
    private var events: Array;
    private var alloc: Allocator;

    private var partitionDict: Object;
    private var partitions: Array;

    private var argPack: Object;

    public var Constants: Object;   // 怎么用全看你自己，反正解决不了的问题就用这个

    public function EventPool()
    {
        this.events = new Array();
        this.alloc = new Allocator(this.events);

        this.partitionDict = new Object();
        this.partitions = new Array();

        this.argPack = new Object();
        this.argPack._parent = this;
        this.argPack.RequiresExec = function (index: Number)
        {
            this._parent.events[index].call(this);
            this._parent.alloc.Free(index);
        };

        this.Constants = new Object();
    }

    public function Insert(事件分区: String, 事件: Function): Number
    {
        var partitionIndex: Number = this.partitionDict[事件分区];
        if (partitionIndex == undefined)
        {
            partitionIndex = this.partitions.length;
            this.partitions.push([]);
            this.partitionDict[事件分区] = partitionIndex;
        }
        
        var index: Number = this.alloc.Alloc(事件);
        this.partitions[partitionIndex].push(index);
        return index;
    }
    public function Exec(事件分区: String, 指定参数: Object): Void
    {
        var partitionIndex: Number = this.partitionDict[事件分区];
        var partition: Array = this.partitions[partitionIndex];
        if ((partitionIndex == undefined) || (partition.length == 0))
        {
            return;
        }

        var args: Object = new Object();
        if (指定参数 == undefined)
        {
            args = this.argPack;
        }
        else
        {
            for (var i in this.argPack)
            {
                args[i] = this.argPack[i];
            }
            for (var i in 指定参数)
            {
                args[i] = 指定参数[i];
            }
        }

        for (var i: Number = 0; i < partition.length; i++)
        {
            this.events[partition[i]].call(args);
            this.alloc.Free(partition[i]);
        }
        delete partition;
        delete this.partitions[partitionIndex];
        this.partitions[partitionIndex] = new Array();
    }

    public function AddArg(参数名: String, 参数值: Object): Void
    {
        this.argPack[参数名] = 参数值;
    }
    public function AddArgs(args): Void
    {
        if (args instanceof Array)
        {
            for (var i = 0; i < args.length; i++)
            {
                this.argPack[args[i][0]] = args[i][1];
            }
        }
        else if (args instanceof Object)
        {
            for (var index in args)
            {
                this.argPack[index] = args[index];
            }
        }
    }
}