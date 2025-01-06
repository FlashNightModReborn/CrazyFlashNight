var test:org.flashNight.naki.Normalization.NormalizationUtilTest = new org.flashNight.naki.Normalization.NormalizationUtilTest();


=== Running Correctness Assertions ===
Assertion Passed: sigmoid(0) should be 0.5
Assertion Passed: sigmoid(1)
Assertion Passed: sigmoid(-1)
Assertion Passed: relu(1) should be 1
Assertion Passed: relu(-1) should be 0
Assertion Passed: relu(0) should be 0
Assertion Passed: leakyRelu(1,0.01) should be 1
Assertion Passed: leakyRelu(-1,0.01) should be -0.01
Assertion Passed: leakyRelu(0,0.01) should be 0
Assertion Passed: softplus(0) should be ln(2)
Assertion Passed: softplus(1)
Assertion Passed: softplus(-1)
Assertion Passed: sig_tyler(0) should be 0.5
Assertion Passed: sig_tyler(10)
Assertion Passed: sig_tyler(-10)
Assertion Passed: tanh(0) should be 0
Assertion Passed: tanh(1)
Assertion Passed: tanh(-1)
Assertion Passed: minMaxNormalize(5,0,10,0,1) should be 0.5
Assertion Passed: minMaxNormalize(0,0,10,-1,1) should be -1
Assertion Passed: minMaxNormalize(10,0,10,-1,1) should be 1
Assertion Passed: zScoreNormalize(10,5,2) should be 2.5
Assertion Passed: zScoreNormalize(5,5,2) should be 0
Assertion Passed: zScoreNormalize(3,5,2) should be -1
Assertion Passed: clamp(5,0,10) should be 5
Assertion Passed: clamp(-5,0,10) should be 0
Assertion Passed: clamp(15,0,10) should be 10
Assertion Passed: softmax([1,2,3]) element 0
Assertion Passed: softmax([1,2,3]) element 1
Assertion Passed: softmax([1,2,3]) element 2
Assertion Passed: normalizeVector([3,4]) first element should be 0.6
Assertion Passed: normalizeVector([3,4]) second element should be 0.8
Assertion Passed: linearScale with originalMin == originalMax should return targetMin
Assertion Failed: linearScale(15,10,20,0,1) should be 0.5 | Expected: 5, Actual: 0.5
Assertion Passed: linearScale(20,10,20,0,1) should be 1
Assertion Passed: exponentialScale(0,2,0,1) should be 1
Assertion Failed: exponentialScale(1,2,0,2) should be 2 | Expected: 2, Actual: 4
Assertion Failed: exponentialScale(2,2,0,4) should be 4 | Expected: 4, Actual: 16

=== Running Deviation Test ===
x: -10, sigmoid(x): 0.0000453978687024344, flt(x): -0.909090909090909, deviation: 0.909136306959611
x: -5, sigmoid(x): 0.00669285092428485, flt(x): -0.833333333333333, deviation: 0.840026184257618
x: -1, sigmoid(x): 0.268941421369995, flt(x): -0.5, deviation: 0.768941421369995
x: -0.5, sigmoid(x): 0.377540668798145, flt(x): -0.333333333333333, deviation: 0.710874002131479
x: 0, sigmoid(x): 0.5, flt(x): 0, deviation: 0.5
x: 0.5, sigmoid(x): 0.622459331201855, flt(x): 0.333333333333333, deviation: 0.289125997868521
x: 1, sigmoid(x): 0.731058578630005, flt(x): 0.5, deviation: 0.231058578630005
x: 5, sigmoid(x): 0.993307149075715, flt(x): 0.833333333333333, deviation: 0.159973815742382
x: 10, sigmoid(x): 0.999954602131298, flt(x): 0.909090909090909, deviation: 0.0908636930403885

=== Running Performance Test ===
x: 0, flt Time: 968ms, sigmoid Time: 1274ms, relu Time: 1156ms, leakyRelu Time: 986ms, softplus Time: 1529ms, sig_tyler Time: 1107ms, tanh Time: 1695ms, minMaxNormalize Time: 1256ms, zScoreNormalize Time: 1026ms, clamp Time: 981ms, softmax Time: 6021ms, normalizeVector Time: 3747ms, linearScale Time: 1251ms, exponentialScale Time: 1339ms
x: 1, flt Time: 980ms, sigmoid Time: 1272ms, relu Time: 1175ms, leakyRelu Time: 939ms, softplus Time: 1517ms, sig_tyler Time: 1137ms, tanh Time: 1672ms, minMaxNormalize Time: 1246ms, zScoreNormalize Time: 1024ms, clamp Time: 998ms, softmax Time: 6080ms, normalizeVector Time: 3799ms, linearScale Time: 1282ms, exponentialScale Time: 1373ms
x: -1, flt Time: 1019ms, sigmoid Time: 1303ms, relu Time: 1192ms, leakyRelu Time: 1000ms, softplus Time: 1541ms, sig_tyler Time: 1167ms, tanh Time: 1704ms, minMaxNormalize Time: 1274ms, zScoreNormalize Time: 1034ms, clamp Time: 979ms, softmax Time: 6051ms, normalizeVector Time: 3729ms, linearScale Time: 1258ms, exponentialScale Time: 1361ms
x: 1.5, flt Time: 991ms, sigmoid Time: 1254ms, relu Time: 1172ms, leakyRelu Time: 951ms, softplus Time: 1511ms, sig_tyler Time: 1148ms, tanh Time: 1656ms, minMaxNormalize Time: 1258ms, zScoreNormalize Time: 1046ms, clamp Time: 999ms, softmax Time: 5976ms, normalizeVector Time: 3729ms, linearScale Time: 1285ms, exponentialScale Time: 1428ms
x: -1.5, flt Time: 1033ms, sigmoid Time: 1276ms, relu Time: 1172ms, leakyRelu Time: 1002ms, softplus Time: 1534ms, sig_tyler Time: 1167ms, tanh Time: 1686ms, minMaxNormalize Time: 1288ms, zScoreNormalize Time: 1076ms, clamp Time: 1027ms, softmax Time: 6075ms, normalizeVector Time: 3783ms, linearScale Time: 1288ms, exponentialScale Time: 1423ms
x: 1000000, flt Time: 995ms, sigmoid Time: 1869ms, relu Time: 1172ms, leakyRelu Time: 939ms, softplus Time: 1915ms, sig_tyler Time: 1501ms, tanh Time: 2489ms, minMaxNormalize Time: 1249ms, zScoreNormalize Time: 1007ms, clamp Time: 956ms, softmax Time: 6010ms, normalizeVector Time: 3747ms, linearScale Time: 1254ms, exponentialScale Time: 2783ms
x: -1000000, flt Time: 993ms, sigmoid Time: 1279ms, relu Time: 1172ms, leakyRelu Time: 974ms, softplus Time: 1529ms, sig_tyler Time: 1525ms, tanh Time: 2506ms, minMaxNormalize Time: 1265ms, zScoreNormalize Time: 1023ms, clamp Time: 934ms, softmax Time: 6070ms, normalizeVector Time: 3792ms, linearScale Time: 1267ms, exponentialScale Time: 1598ms
x: 1.79769313486231e+308, flt Time: 1092ms, sigmoid Time: 1993ms, relu Time: 1280ms, leakyRelu Time: 960ms, softplus Time: 2049ms, sig_tyler Time: 2681ms, tanh Time: 2868ms, minMaxNormalize Time: 1665ms, zScoreNormalize Time: 1236ms, clamp Time: 1004ms, softmax Time: 6039ms, normalizeVector Time: 3772ms, linearScale Time: 1646ms, exponentialScale Time: 1909ms
x: -1.79769313486231e+308, flt Time: 1204ms, sigmoid Time: 1408ms, relu Time: 1180ms, leakyRelu Time: 1092ms, softplus Time: 1665ms, sig_tyler Time: 2661ms, tanh Time: 2828ms, minMaxNormalize Time: 1640ms, zScoreNormalize Time: 1231ms, clamp Time: 965ms, softmax Time: 6090ms, normalizeVector Time: 3815ms, linearScale Time: 1644ms, exponentialScale Time: 1450ms
x: 4.94065645841247e-324, flt Time: 1813ms, sigmoid Time: 1952ms, relu Time: 2073ms, leakyRelu Time: 1401ms, softplus Time: 2211ms, sig_tyler Time: 1979ms, tanh Time: 3617ms, minMaxNormalize Time: 1329ms, zScoreNormalize Time: 1676ms, clamp Time: 1919ms, softmax Time: 6013ms, normalizeVector Time: 3750ms, linearScale Time: 1296ms, exponentialScale Time: 2819ms
x: -4.94065645841247e-324, flt Time: 2370ms, sigmoid Time: 1959ms, relu Time: 1631ms, leakyRelu Time: 1580ms, softplus Time: 2200ms, sig_tyler Time: 1956ms, tanh Time: 3554ms, minMaxNormalize Time: 1296ms, zScoreNormalize Time: 1633ms, clamp Time: 1915ms, softmax Time: 6009ms, normalizeVector Time: 3739ms, linearScale Time: 1302ms, exponentialScale Time: 2829ms
x: Infinity, flt Time: 1466ms, sigmoid Time: 1823ms, relu Time: 1271ms, leakyRelu Time: 952ms, softplus Time: 1892ms, sig_tyler Time: 2644ms, tanh Time: 2619ms, minMaxNormalize Time: 2031ms, zScoreNormalize Time: 1435ms, clamp Time: 992ms, softmax Time: 6017ms, normalizeVector Time: 3778ms, linearScale Time: 2031ms, exponentialScale Time: 1837ms
x: -Infinity, flt Time: 1689ms, sigmoid Time: 1244ms, relu Time: 1187ms, leakyRelu Time: 1191ms, softplus Time: 1505ms, sig_tyler Time: 2634ms, tanh Time: 2613ms, minMaxNormalize Time: 2027ms, zScoreNormalize Time: 1447ms, clamp Time: 969ms, softmax Time: 6019ms, normalizeVector Time: 3773ms, linearScale Time: 2030ms, exponentialScale Time: 1345ms
x: NaN, flt Time: 1574ms, sigmoid Time: 2558ms, relu Time: 1364ms, leakyRelu Time: 1302ms, softplus Time: 2799ms, sig_tyler Time: 3258ms, tanh Time: 4274ms, minMaxNormalize Time: 2445ms, zScoreNormalize Time: 1637ms, clamp Time: 1047ms, softmax Time: 6020ms, normalizeVector Time: 3760ms, linearScale Time: 2448ms, exponentialScale Time: 2134ms
