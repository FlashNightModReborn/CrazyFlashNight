import org.flashNight.naki.RandomNumberEngine.*;

// 获取粉噪音实例
var pinkNoise:PinkNoiseEngine = PinkNoiseEngine.getInstance();

// 生成样本数据
var samples:Array = new Array();
for (var i:Number = 0; i < 3000; i++) {
    var sample:Number = pinkNoise.nextFloat();
    samples.push(sample);
    // trace("Sample " + i + ": " + sample);
}

// 计算离散傅里叶变换（DFT）并求取功率谱密度（PSD）
// 这里只计算前 N/2 个频率分量（因为对称）
var N:Number = samples.length;
var psd:Array = new Array();
for (var k:Number = 0; k <= N/2; k++) {
    var re:Number = 0;
    var im:Number = 0;
    for (var n:Number = 0; n < N; n++) {
        var angle:Number = 2 * Math.PI * k * n / N;
        re += samples[n] * Math.cos(angle);
        im += samples[n] * Math.sin(angle);
    }
    var power:Number = re * re + im * im;
    psd.push(power);
    // trace("Frequency bin " + k + ": Power = " + power);
}

// 对 k=1 到 floor(N/2) 的频率分量进行 log-log 线性回归计算斜率
// （注意：k=0 是直流分量，不参与回归）
var sumX:Number = 0;
var sumY:Number = 0;
var sumXY:Number = 0;
var sumX2:Number = 0;
var count:Number = Math.floor(N/2);
for (var k:Number = 1; k <= count; k++) {
    // 归一化频率（假设采样频率 fs = 1）
    var frequency:Number = k / N;
    // 计算对数（底数10）
    var logF:Number = Math.log(frequency) / Math.LN10;
    var logP:Number = Math.log(psd[k]) / Math.LN10;
    
    sumX += logF;
    sumY += logP;
    sumXY += logF * logP;
    sumX2 += logF * logF;
}
var slope:Number = (count * sumXY - sumX * sumY) / (count * sumX2 - sumX * sumX);

// 判断斜率是否符合理想粉红噪音（理想约 -1，允许误差在 0.2 内）
var tolerance:Number = 0.2;
var resultMsg:String = "计算的斜率为: " + slope + "\n";
if (Math.abs(slope + 1) <= tolerance) {
    resultMsg += "符合理想的粉红噪音斜率 (大约 -1)";
} else {
    resultMsg += "不符合理想的粉红噪音斜率 (大约 -1)";
}
trace(resultMsg);
