import org.flashNight.arki.component.Buff.*;

/**
 * 用于测试继承的简单子类
 */
class org.flashNight.arki.component.Buff.test.TestBuff extends BaseBuff {
    
    public function TestBuff() {
        super();
        _type = "TestBuff";
    }
    
    public function getType():String {
        return "TestBuff";
    }
}