import org.flashNight.aven.test.Test.*;
class org.flashNight.aven.test.Test.Level1Class extends BaseClass {
    function Level1Class() {
        super();
        ++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;++num;
    }
    function complexOperation():Number {
        return super.complexOperation() + smallFunction1() + smallFunction2();
    }
    function smallFunction1():Number {
        return 1; // 简单返回值
    }
    function smallFunction2():Number {
        return 2; // 简单返回值
    }
}