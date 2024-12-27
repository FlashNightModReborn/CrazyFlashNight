// org.flashNight.aven.test.FlatClass.as
class org.flashNight.aven.test.Test.FlatClass {
    var num;
    function FlatClass() {
        num = 0;
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
    }

    function complexOperation():Number {
        // 将所有小函数直接展开到这里，等价于 FinalClass 的任务
        var sum = smallFunction1();
        sum += smallFunction2();
        sum += smallFunction3();
        sum += smallFunction4();
        sum += smallFunction5();
        return sum;
    }

    function smallFunction1():Number { return 1; }
    function smallFunction2():Number { return 2; }
    function smallFunction3():Number { return 3; }
    function smallFunction4():Number { return 4; }
    function smallFunction5():Number { return 5; }
}
