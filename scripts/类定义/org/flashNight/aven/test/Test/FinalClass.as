import org.flashNight.aven.test.Test.*;
class org.flashNight.aven.test.Test.FinalClass extends Level2Class {
    function FinalClass() {
        super();
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
    }
    function complexOperation():Number {
        return super.complexOperation() + smallFunction5();
    }
    function smallFunction5():Number {
        return 5; // 简单返回值
    }
}