class org.flashNight.gesh.array.PrimeSpectrumMapper {
    private static var DEFAULT_PRIMES:Array = [2,3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97];
    
    private var _primeList:Array;
    private var _minPrime:Number;
    private var _maxPrime:Number;
    
    public function PrimeSpectrumMapper(primeList:Array) {
        trace("===== Constructor =====");
        if (primeList == null) {
            trace("Using DEFAULT_PRIMES");
            primeList = DEFAULT_PRIMES;
        } else {
            trace("Using custom prime list");
        }
        
        this._primeList = primeList.concat().sort(Array.NUMERIC);
        this._minPrime = this._primeList[0];
        this._maxPrime = this._primeList[this._primeList.length - 1];
        
        trace("Initialized Prime List: " + this._primeList);
        trace("MinPrime: " + this._minPrime + " MaxPrime: " + this._maxPrime);
        trace("=======================");
    }
    
    public function mapToPrimeSpectrum(sourceArr:Array, scaleMode:String):Array {
        trace("\n===== mapToPrimeSpectrum =====");
        trace("Input Array: " + sourceArr);
        trace("Scale Mode: " + scaleMode);
        
        if (sourceArr.length == 0) return [];
        
        var analyzed:Object = _analyzeSource(sourceArr);
        scaleMode = scaleMode.toLowerCase();
        var result:Array = [];
        
        trace("Analyzed Source - Min: " + analyzed.min + " Max: " + analyzed.max + " Range: " + analyzed.range);
        
        // Pre-generate primes for fit mode
        if (scaleMode == "fit") {
            var requiredPrimes:Number = sourceArr.length;
            if (this._primeList.length < requiredPrimes) {
                _generatePrimesByCount(requiredPrimes);
            }
        }
        
        for (var i:Number = 0; i < sourceArr.length; i++) {
            trace("\n--- Processing Element " + i + " ---");
            var val:Number = sourceArr[i];
            trace("Raw Value: " + val);
            var prime:Number;
            
            switch(scaleMode) {
                case "clip":
                    trace("[Clip Mode] Direct nearest prime search");
                    prime = _getNearestPrime(val);
                    break;
                    
                case "expand":
                    trace("[Expand Mode] Dynamic prime generation");
                    if (val > this._maxPrime) {
                        trace("Need to generate primes up to: " + val);
                        _generatePrimesUpTo(val);
                    }
                    prime = _getNearestPrime(val);
                    break;
                    
                case "fit":
                default:
                    trace("[Fit Mode] Scaling based on prime values");
                    var fitPrimes:Array = this._primeList.slice(0, sourceArr.length);
                    var fitMinVal:Number = analyzed.min;
                    var fitMaxVal:Number = analyzed.max;
                    var primeMin:Number = fitPrimes[0];
                    var primeMax:Number = fitPrimes[fitPrimes.length - 1];
                    
                    // 线性映射到质数范围
                    var scaledVal:Number = (val - fitMinVal) / (fitMaxVal - fitMinVal) * (primeMax - primeMin) + primeMin;
                    prime = _getNearestPrime(scaledVal, fitPrimes);
                    trace("Scaled Value: " + scaledVal);
                    break;
            }
            
            trace("Selected Prime: " + prime);
            result.push(prime);
        }
        
        trace("Final Result: " + result);
        trace("=======================");
        return result;
    }
    
    private function _generatePrimesByCount(count:Number):Void {
        trace("\n--- Generating " + count + " primes ---");
        while (this._primeList.length < count) {
            var nextPrime:Number = _getNextPrime(this._maxPrime);
            this._primeList.push(nextPrime);
            this._maxPrime = nextPrime;
            trace("Generated New Prime: " + nextPrime);
        }
        this._primeList.sort(Array.NUMERIC);
        this._minPrime = this._primeList[0];
        this._maxPrime = this._primeList[this._primeList.length - 1];
        trace("Updated Prime List: " + this._primeList);
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
        trace("\n--- Generating Primes Up To " + target + " ---");
        trace("Current MaxPrime: " + this._maxPrime);
        
        while (this._maxPrime < target) {
            var nextPrime:Number = _getNextPrime(this._maxPrime);
            trace("Generated New Prime: " + nextPrime);
            this._primeList.push(nextPrime);
            this._maxPrime = nextPrime;
        }
        
        this._primeList.sort(Array.NUMERIC);
        this._minPrime = this._primeList[0];
        this._maxPrime = this._primeList[this._primeList.length - 1];
        
        trace("Updated Prime List: " + this._primeList);
        trace("New MinPrime: " + this._minPrime + " New MaxPrime: " + this._maxPrime);
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
    
    private function _getNearestPrime(val:Number, specificList:Array):Number {
        var primeList:Array = specificList || this._primeList;
        var minPrime:Number = primeList[0];
        var maxPrime:Number = primeList[primeList.length - 1];
        
        trace("\n--- Finding Nearest Prime for " + val + " ---");
        trace("Prime List: " + primeList);
        
        if (val <= minPrime) return minPrime;
        if (val >= maxPrime) return maxPrime;
        
        // Linear search for exact nearest
        var nearest:Number = minPrime;
        var minDist:Number = Infinity;
        for (var i:Number = 0; i < primeList.length; i++) {
            var dist:Number = Math.abs(primeList[i] - val);
            if (dist < minDist || (dist == minDist && primeList[i] < nearest)) {
                nearest = primeList[i];
                minDist = dist;
            }
        }
        return nearest;
    }
}