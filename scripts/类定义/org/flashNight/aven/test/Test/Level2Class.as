import org.flashNight.aven.test.Test.*;
class org.flashNight.aven.test.Test.Level2Class extends Level1Class {
    function Level2Class() {
        super();
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
    }
    function complexOperation():Number {
        return super.complexOperation() + smallFunction3() + smallFunction4();
    }
    function smallFunction3():Number {
        return 3; // 简单返回值
    }
    function smallFunction4():Number {
        return 4; // 简单返回值
    }
}