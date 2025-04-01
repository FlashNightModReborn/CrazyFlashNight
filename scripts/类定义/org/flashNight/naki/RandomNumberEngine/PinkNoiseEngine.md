import org.flashNight.naki.RandomNumberEngine.*;

// 获取粉噪音实例
var pinkNoise:PinkNoiseEngine = PinkNoiseEngine.getInstance();

// 样本数量调整为2的幂，有利于 FFT 计算
var sampleCount:Number = 65536 * 4;
var samples:Array = new Array();
for (var i:Number = 0; i < sampleCount; i++) {
    var sample:Number = pinkNoise.nextFloat();
    samples.push(sample);
}

// 将实数样本转换为复数形式，构成 FFT 输入（im 分量置 0）
var complexSamples:Array = new Array();
for (var i:Number = 0; i < sampleCount; i++) {
    complexSamples.push({re: samples[i], im: 0});
}

/**
 * Cooley-Tukey FFT 实现（迭代版本）
 * 输入数组 input 中每个元素为 {re, im}，数组长度必须为 2 的幂。
 * 返回值为 FFT 结果（复数数组）。
 */
function fft(input:Array):Array {
    var n:Number = input.length;
    
    // 先进行位反转置换
    var j:Number = 0;
    for (var i:Number = 0; i < n; i++) {
        if (i < j) {
            var tmp:Object = input[i];
            input[i] = input[j];
            input[j] = tmp;
        }
        var m:Number = n >> 1;
        while (j >= m && m > 0) {
            j -= m;
            m >>= 1;
        }
        j += m;
    }
    
    // 迭代方式进行 FFT 计算
    for (var len:Number = 2; len <= n; len <<= 1) {
        // 计算每一层所需旋转因子：wlen = exp(-2πi/len)
        var angle:Number = -2 * Math.PI / len;
        var wlen:Object = { re: Math.cos(angle), im: Math.sin(angle) };
        for (var i:Number = 0; i < n; i += len) {
            var w:Object = { re: 1, im: 0 };
            // 对每个蝶形运算
            for (var k:Number = 0; k < len/2; k++) {
                var u:Object = input[i + k];
                var v:Object = input[i + k + len/2];
                // 计算 v * w
                var t:Object = {
                    re: v.re * w.re - v.im * w.im,
                    im: v.re * w.im + v.im * w.re
                };
                // 更新蝶形节点
                input[i + k] = { re: u.re + t.re, im: u.im + t.im };
                input[i + k + len/2] = { re: u.re - t.re, im: u.im - t.im };
                // 旋转 w
                var wTemp:Object = {
                    re: w.re * wlen.re - w.im * wlen.im,
                    im: w.re * wlen.im + w.im * wlen.re
                };
                w = wTemp;
            }
        }
    }
    return input;
}

// 使用 FFT 计算频谱
var fftResult:Array = fft(complexSamples);

// 计算功率谱密度（PSD）：仅取前 sampleCount/2 个频率分量（对称性）
var psd:Array = new Array();
var halfCount:Number = sampleCount / 2;
for (var k:Number = 0; k <= halfCount; k++) {
    var re:Number = fftResult[k].re;
    var im:Number = fftResult[k].im;
    var power:Number = re * re + im * im;
    psd.push(power);
}

// 对 k=1 到 halfCount 的频率分量进行 log-log 线性回归，计算斜率
var sumX:Number = 0;
var sumY:Number = 0;
var sumXY:Number = 0;
var sumX2:Number = 0;
var count:Number = halfCount;
for (var k:Number = 1; k <= count; k++) {
    // 归一化频率（采样频率 fs = 1 的假设）
    var frequency:Number = k / sampleCount;
    // 使用底10对数
    var logF:Number = Math.log(frequency) / Math.LN10;
    var logP:Number = Math.log(psd[k]) / Math.LN10;
    
    sumX += logF;
    sumY += logP;
    sumXY += logF * logP;
    sumX2 += logF * logF;
}
var slope:Number = (count * sumXY - sumX * sumY) / (count * sumX2 - sumX * sumX);

// 判断斜率是否符合理想粉红噪音（约 -1，允许误差 0.2）
var tolerance:Number = 0.2;
var resultMsg:String = "计算的斜率为: " + slope + "\n";
if (Math.abs(slope + 1) <= tolerance) {
    resultMsg += "符合理想的粉红噪音斜率 (大约 -1)";
} else {
    resultMsg += "不符合理想的粉红噪音斜率 (大约 -1)";
}
trace(resultMsg);
