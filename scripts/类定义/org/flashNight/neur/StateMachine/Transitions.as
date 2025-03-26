import org.flashNight.neur.StateMachine.FSM_Status;

class org.flashNight.neur.StateMachine.Transitions {
    private var status:FSM_Status; //目标状态
    private var lists:Object; //过渡线列表

    public function Transitions(_status:FSM_Status){
        this.status = _status;
        this.lists = new Object();
    }

    // 为一个子状态新增一条优先级最低的过渡线
    public function push(current:String,target:String,func:Function):Void{
        var list = this.lists[current];
        if(list == null){
            list = new Array();
            this.lists[current] = list;
        }
        list.push({
            target:target,
            active:true,
            func:func
        });
    }

    // 为一个子状态新增一条优先级最高的过渡线
    public function unshift(current:String,target:String,func:Function):Void{
        var list = this.lists[current];
        if(list == null){
            list = new Array();
            this.lists[current] = list;
        }
        list.unshift({
            target:target,
            active:true,
            func:func
        });
    }

    public function Transit(current:String):String{
        var list = this.lists[current];
        //按顺序依次执行过渡函数
        for(var i:Number = 0; i < list.length; i++){
            var transition = list[i];
            if(transition.active !== true) continue;
            if(transition.func.call(status) === true){
                return transition.target;
            }
        }
        return null;
    }
}
