_root.改装系统 = new Object();
_root.改装系统.当前页数 = 1;

_root.改装系统.加载改装清单 = function(清单){
    _root.改装系统.当前页数 = 1;
    var 物品改装界面 = _root.从库中加载外部UI("物品改装界面");
    物品改装界面.改装清单 = _root.改装清单[清单];
        物品改装界面.titleText.text = 清单 == "默认" ? "装备改装" : 清单;
        
    if(物品改装界面._currentframe > 1){
        物品改装界面.gotoAndPlay("刷新");
    }
}

_root.改装系统.初始化奖励块 = function(){
    this.图纸块列表 = new Array(20);
    for (var xMoveNumbers = 0; xMoveNumbers < 2; xMoveNumbers++){
        for (var yMoveNumbers = 0; yMoveNumbers < 10; yMoveNumbers++){
            var index = xMoveNumbers * 10 + yMoveNumbers;
            this.图纸块列表[index] = this.图纸块.duplicateMovieClip("图纸块" + index, index,{
                _x:xMoveNumbers * 244 + 8, 
                _y:yMoveNumbers * 28 + 30,
                _visible: false
            });
        }
    }
    this.图纸块._visible = false;
    this.gotoAndStop("正常");
}

_root.改装系统.排列奖励块 = function(){
    var startIndex =  20 * (_root.改装系统.当前页数 - 1);
    for (var i = 0; i < 20; i++){
        var index = i + startIndex;
        var 当前图纸块 = this.图纸块列表[i];
        if(index >= this.改装清单.length){
            当前图纸块._visible = false;
            continue;
        }
        当前图纸块._visible = true;
        var 当前物品 = this.改装清单[index];
        if(isNaN(当前物品.value)) 当前物品.value = 1;
        当前图纸块.改装信息 = 当前物品;
        当前图纸块.标题 = 当前物品.title;
        当前图纸块.多语言标题 = _root.getItemData(当前物品.name).displayname;
        if(当前物品.value > 1) 当前图纸块.多语言标题 += " * " + 当前物品.value;
        当前图纸块.数量 = 当前物品.value;
        当前图纸块.价格 = 当前物品.price;
        当前图纸块.K点价格 = 当前物品.kprice;
        当前图纸块.数组号 = index;
        当前图纸块.刷新();
    }
}

_root.改装系统.删除奖励块 = function(){
    for (var i = 0; i < 20; i++){
        this.图纸块列表[i]._visible = false;
    }
}

_root.改装系统.向前翻页 = function(){
    if(_root.改装系统.当前页数 > 1){
        _root.改装系统.当前页数 -= 1;
        _parent.页数text.text = _root.改装系统.当前页数;
        _parent.删除奖励块();
        _parent.排列奖励块(_root.改装系统.当前页数);
    }
}
_root.改装系统.向后翻页 = function(){
        if(_parent.改装清单.length >= _root.改装系统.当前页数 * _parent.每页显示数){
        _root.改装系统.当前页数 += 1;
        _parent.页数text.text = _root.改装系统.当前页数;
        _parent.删除奖励块();
        _parent.排列奖励块(_root.改装系统.当前页数);
    }
}

_root.改装系统.获取材料个数 = function(itemData, name, val){
    if(itemData.type == "武器" || itemData.type == "防具"){
        if(val > 1) return "+" + val;
        return "";
    }
    var 持有数量 = 0;
    if(itemData.use == "情报"){
        持有数量 = _root.收集品栏.情报.getValue(name);
        if(持有数量 >= val) return "<FONT COLOR=\'#66FF66\'>已持有</FONT>";
    }else if(itemData.use == "材料"){
        持有数量 = _root.收集品栏.材料.getValue(name);
    }else{
        持有数量 = _root.物品栏.背包.getTotal(name) + _root.物品栏.药剂栏.getTotal(name);
    }
    var color = 持有数量 < val ? "\'#FF3333\'" : "\'#66FF66\'";
    return "<FONT COLOR=" + color + ">" + 持有数量 + " / " + val + "</FONT>";
}



_root.挂载物品完整装扮 = function(){
    var 显示图标 = this.attachMovie(_parent.图标,"图标",this.getNextHighestDepth());
    var mask_size = 17;
    var border_thickness = 1; // 边框的厚度

    switch(_root.getItemData(_parent._parent.改装信息[1]).use)
    {
        case '长枪':
        case '手枪':
        case '刀':
            var maskMC:MovieClip = this.createEmptyMovieClip("maskMC", this.getNextHighestDepth());
            显示图标.gotoAndStop(2);
            显示图标._rotation += 45;
            显示图标._xscale = 显示图标._yscale = 50;

            // 绘制遮罩层
            maskMC.beginFill(0xFFFFFF);
            maskMC.moveTo(-mask_size, -mask_size);
            maskMC.lineTo(mask_size, -mask_size);
            maskMC.lineTo(mask_size, mask_size);
            maskMC.lineTo(-mask_size, mask_size);
            maskMC.lineTo(-mask_size, -mask_size);
            maskMC.endFill();
            显示图标.setMask(maskMC); // 将遮罩层应用到显示图标上

            // 创建并绘制边框
            var borderMC:MovieClip = this.createEmptyMovieClip("borderMC", this.getNextHighestDepth());
            borderMC.lineStyle(border_thickness, 0xFFFFFF); // 设置线条样式
            borderMC.moveTo(-mask_size, -mask_size);
            borderMC.lineTo(mask_size, -mask_size);
            borderMC.lineTo(mask_size, mask_size);
            borderMC.lineTo(-mask_size, mask_size);
            borderMC.lineTo(-mask_size, -mask_size);

            显示图标._x = maskMC._x = borderMC._x -= 2;
            break;

        default:
            显示图标._xscale = 显示图标._yscale = 145;
            显示图标._x -= 1;
            break;
    }

    if(this.图标._x != undefined) 
    {
        this.基本款._visible = 0;
    } else 
    {
        this.基本款._visible = 1;
    }
}
