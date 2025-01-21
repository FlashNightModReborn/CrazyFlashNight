class org.flashNight.gesh.array.PrimeSpectrumMapper {
    private static var DEFAULT_PRIMES:Array = [2,3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97];
    
    private var _primeList:Array;
    private var _minPrime:Number;
    private var _maxPrime:Number;
    
    public function PrimeSpectrumMapper(primeList:Array) {
        if (primeList == null) primeList = DEFAULT_PRIMES;
        this._primeList = primeList.concat().sort(Array.NUMERIC);
        this._minPrime = this._primeList[0];
        this._maxPrime = this._primeList[this._primeList.length - 1];
    }
    
    public function mapToPrimeSpectrum(sourceArr:Array, scaleMode:String):Array {
        if (sourceArr.length == 0) return [];
        
        var analyzed:Object = _analyzeSource(sourceArr);
        scaleMode = scaleMode.toLowerCase();
        var result:Array = [];
        
        for (var i:Number = 0; i < sourceArr.length; i++) {
            var val:Number = sourceArr[i];
            var prime:Number;
            
            switch(scaleMode) {
                case "clip":
                    prime = _getNearestPrime(val);
                    break;
                    
                case "expand":
                    analyzed = _analyzeSource(sourceArr);
                    if (analyzed.max > this._maxPrime) _generatePrimesUpTo(analyzed.max);
                    var targetMin:Number = this._minPrime;
                    var targetMax:Number = this._maxPrime;
                    var expandScale:Number = (targetMax - targetMin) / (analyzed.range || 1);
                    var scaledVal:Number = targetMin + (val - analyzed.min) * expandScale;
                    prime = _getNearestPrime(scaledVal);
                    break;
                    
                case "fit":
                default:
                    var targetMin:Number = this._minPrime;
                    var targetMax:Number = this._maxPrime;
                    var fitScale:Number = (targetMax - targetMin) / (analyzed.range || 1);
                    var scaledVal:Number = targetMin + (val - analyzed.min) * fitScale;
                    prime = _getNearestPrime(scaledVal);
                    break;
            }
            result.push(prime);
        }
        return result;
    }
    
    private function _analyzeSource(arr:Array):Object {
        var minVal:Number = Infinity, maxVal:Number = -Infinity;
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] < minVal) minVal = arr[i];
            if (arr[i] > maxVal) maxVal = arr[i];
        }
        return {min: minVal, max: maxVal, range: maxVal - minVal};
    }
    
    private function _generatePrimesUpTo(target:Number):Void {
        while (this._maxPrime < target) {
            var nextPrime:Number = _getNextPrime(this._maxPrime);
            this._primeList.push(nextPrime);
            this._maxPrime = nextPrime;
        }
        this._primeList.sort(Array.NUMERIC);
    }
    
    private function _getNextPrime(lastPrime:Number):Number {
        var candidate:Number = lastPrime + 1;
        while (!_isPrime(candidate)) candidate++;
        return candidate;
    }
    
    private function _isPrime(num:Number):Boolean {
        if (num < 2) return false;
        for (var i:Number = 2; i <= Math.sqrt(num); i++) {
            if (num % i == 0) return false;
        }
        return true;
    }
    
    private function _getNearestPrime(val:Number):Number {
        if (val <= this._minPrime) return this._minPrime;
        if (val >= this._maxPrime) return this._maxPrime;
        
        // 精确匹配检查
        for (var i:Number = 0; i < this._primeList.length; i++) {
            if (this._primeList[i] == val) return val;
        }
        
        // 二分查找修正
        var low:Number = 0, high:Number = this._primeList.length - 1;
        var nearest:Number = this._primeList[high];
        while (low <= high) {
            var mid:Number = (low + high) >> 1;
            var current:Number = this._primeList[mid];
            if (current == val) return current;
            
            var currentDist:Number = Math.abs(current - val);
            var nearestDist:Number = Math.abs(nearest - val);
            if (currentDist < nearestDist || (currentDist == nearestDist && current < nearest)) {
                nearest = current;
            }
            
            if (current < val) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        return nearest;
    }
}