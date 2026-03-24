import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;
import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangZobrist {
    private var _size:Number;
    private var _table:Array;  // [size][size][2] each {hi, lo}
    private var _hashHi:Number;
    private var _hashLo:Number;

    public function GobangZobrist(size:Number) {
        _size = size;
        _hashHi = 0;
        _hashLo = 0;
        _initTable();
    }

    private function _initTable():Void {
        var rng:SeededLinearCongruentialEngine = new SeededLinearCongruentialEngine(42);
        _table = [];
        for (var i:Number = 0; i < _size; i++) {
            _table[i] = [];
            for (var j:Number = 0; j < _size; j++) {
                _table[i][j] = [];
                // roleIndex 0 = black (role=1), roleIndex 1 = white (role=-1)
                _table[i][j][0] = {hi: rng.next(), lo: rng.next()};
                _table[i][j][1] = {hi: rng.next(), lo: rng.next()};
            }
        }
    }

    public function togglePiece(x:Number, y:Number, role:Number):Void {
        var ri:Number = GobangConfig.roleIndex(role);
        var entry:Object = _table[x][y][ri];
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