import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangZobrist {
    private var _size:Number;
    private var _table:Array;  // [(i*SZ+j)*2+r] each {hi, lo}, length=450
    private var _hashHi:Number;
    private var _hashLo:Number;

    // 棋盘尺寸常量（冻结为 15 路）
    private static var SZ:Number = 15;

    public function GobangZobrist(size:Number) {
        _size = size;
        _hashHi = 0;
        _hashLo = 0;
        _initTable();
    }

    private function _initTable():Void {
        var rng:SeededLinearCongruentialEngine = new SeededLinearCongruentialEngine(42);
        _table = new Array(450);
        for (var i:Number = 0; i < _size; i++) {
            for (var j:Number = 0; j < _size; j++) {
                var idx:Number = (i * SZ + j) * 2;
                // roleIndex 0 = black (role=1), roleIndex 1 = white (role=-1)
                _table[idx] = {hi: rng.next(), lo: rng.next()};
                _table[idx + 1] = {hi: rng.next(), lo: rng.next()};
            }
        }
    }

    public function togglePiece(x:Number, y:Number, role:Number):Void {
        var ri:Number = GobangConfig.roleIndex(role);
        var entry:Object = _table[(x * SZ + y) * 2 + ri];
        _hashHi = _hashHi ^ entry.hi;
        _hashLo = _hashLo ^ entry.lo;
    }

    public function getHashHi():Number {
        return _hashHi;
    }

    public function getHashLo():Number {
        return _hashLo;
    }

    public function toKey():String {
        return String(_hashHi) + "_" + String(_hashLo);
    }

    public function getTable():Array {
        return _table;
    }
}