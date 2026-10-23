/**
 * MeridiansPanel — 经脉系统 Web 面板。
 *
 * 数据权威在 AS2（MeridianPanelService）：配置、点亮集、K点余额、情报持有、四类收益预算
 * 全部经 meridiansState 回包；点亮经 meridianLight 提交，Web 只做呈现与意图收集，
 * 不本地判定价格/门槛/结果（见 workbench-ui-system §1）。
 * 预算分四类（内力 / HP上限 / MP上限 / 防御），每穴按 bonusType 计入对应预算，逐类独立封顶。
 * 右侧只放脉络介绍与情报提示（作者要求不再出穴位栏位）；贯注入口在图上：
 * 点击穴位 → 图下方动作条，按序/预算/K点不足都在那里给原因。
 */
var MeridiansPanel = (function() {
    'use strict';

    var DESIGN_WIDTH = 1404;
    var DESIGN_HEIGHT = 790;

    // ── 人体经脉图（viewBox 420×780，正面观）──
    // 全身轮廓为对参考图的逐像素精细临摹（应作者要求照原图一点一点描摹，版权风险由项目方自担）：
    // 暖色掩码（皮肤/头发/描线；亮部要求 r-b>28 剔除原图边缘 JPEG 暖晕、暗部要求 r-b>6 剔除
    // 中性文字抗锯齿，蓝灰背景与蓝色高亮线天然排除）→ 字芯（灰黑/棕）膨胀 4px 域内剔除非强皮肤
    // 光晕 → 穴位标签框修正（band=框内皮肤带重绘；edge=上下锚点行臂右缘线性内插重绘外缘，用于
    // 天泉/曲泽等贴边标签；fill=蓝经线拱缝整框回填）→ 最大连通域 → 封闭细缝回填
    // （内切半径<6px 的着色缝隙抹平，腋下/肘部/指缝等真实空隙保留为 evenodd 空洞）→
    // Marching Squares 提取真实边界 → RDP 0.5px 简化。头顶含发际轮廓，五指逐根描摹。
    // 管线脚本迭代记录见会话 tmp trace14.js（v14 定稿）。
    var BODY_OUTLINE_D =
        'M240 34.6L237.6 32.1L234.9 29.6L232.2 27.6L229.9 25.7L225.8 23.7L221 22.4L215.2 21.2L207 20.6L19'
        + '8.2 22L191.9 23.9L186.6 26.5L183.2 29.3L179.9 32.5L176.2 37.3L174 42.6L172.6 50.4L172.3 57.5L173'
        + '.7 67.3L171.8 65.3L170.9 66.2L169.3 66.2L167.2 70.7L167.2 74.1L168 74.9L168.8 79.9L171.3 84.9L17'
        + '2.2 89L173 90.7L175.9 93.6L177.2 94L178 95.7L178 98.2L178.8 99L178.8 101.5L180.5 104L180.5 105.7'
        + 'L183.8 109.8L183.8 120.6L183 121.5L183 124L181.7 125.2L171.8 130.2L170.1 130.2L168.4 131.9L165.9'
        + ' 131.9L164.3 133.5L162.6 133.5L158.4 136.8L153.5 139.3L151 139.3L148.5 141L142.7 141.8L141.8 142'
        + '.7L140.2 142.7L138.5 144.3L135.2 145.2L133.5 146.8L131 146.8L129.3 148.5L121 152.6L118.1 155.6L1'
        + '18.1 156.4L115.6 158.9L115.6 160.5L113.1 163L113.1 164.7L111.5 167.2L110.6 173L109 176.3L109 183'
        + '.8L108.1 184.7L108.1 188L107.3 188.8L107.3 202.9L108.1 203.8L108.1 209.6L109 210.4L109 217.1L108'
        + '.1 217.9L107.3 224.6L106.5 225.4L105.7 232L104.8 232.9L104.8 240.4L104 241.2L104 266.1L103.2 267'
        + 'L103.2 270.3L102.3 271.1L100.7 277.8L99 281.1L97.3 282.8L95.7 286.1L95.7 287.8L94 289.4L94 291.1'
        + 'L92.3 293.6L92.3 295.2L90.7 296.9L90.7 298.6L89.9 299.4L89.9 301.1L89 301.9L89 303.6L88.2 304.4L'
        + '88.2 306L86.5 309.4L86.5 311.9L85.7 312.7L85.7 314.4L84.9 315.2L84.9 318.5L84 319.3L84 322.7L83.'
        + '2 323.5L83.2 326L82.4 326.8L82.4 338.5L81.5 339.3L81.5 341L79.9 344.3L79.9 346.8L78.2 349.3L78.2'
        + ' 350.9L76.6 353.4L76.6 355.9L74.9 358.4L73.2 365.1L71.6 367.6L71.6 370.9L69.9 372.6L69.9 374.2L6'
        + '8.2 376.7L67.4 380.9L65.7 382.5L64.1 385.9L62 386.3L58.7 388.8L54.5 390.4L50.4 394.6L49.5 394.6L'
        + '49.1 395.8L47 397.9L46.2 397.9L38.3 406.7L38.3 407.5L36.6 409.1L35.8 411.6L34.1 413.3L32.5 416.6'
        + 'L33.3 420L34.6 421.2L37.1 421.2L37.9 420.4L40.4 420.4L42 419.5L47.9 413.7L49.5 412.9L49.9 413.3L'
        + '49.1 415L49.1 420L48.3 420.8L48.3 422.4L47.4 423.3L47.4 424.9L45.8 428.3L45 433.3L43.3 435.8L43.'
        + '3 438.2L41.6 441.6L41.6 445.7L40.8 446.6L40.8 449.1L40 449.9L40 456.5L42 458.6L44.5 458.6L48.7 4'
        + '55.3L49.1 460.7L52 463.6L55.3 463.6L58.3 460.7L58.3 459.9L60.3 457.8L61.2 457.8L61.6 460.7L64.5 '
        + '463.6L66.2 463.6L69.9 460.7L71.6 457.4L72.4 453.2L74.5 449.5L74.9 450.7L77.8 453.6L79.5 453.6L82'
        + '.4 451.6L84.9 446.6L86.5 439.9L91.5 429.9L91.5 428.3L92.3 427.4L92.3 424.1L93.2 423.3L93.2 420.8'
        + 'L94 420L94 416.6L95.7 413.3L95.7 401.7L95.4 400.2L94.8 395.8L94 395L94 393.3L95.3 392.9L98.2 390'
        + 'L98.2 388.4L99.8 385.9L99.8 384.2L101.5 381.7L101.5 380L104 376.7L105.7 373.4L105.7 371.7L108.1 '
        + '369.2L109.8 365.1L111.5 363.4L113.1 360.1L115.6 357.6L115.6 356.8L119 352.6L119.8 350.1L121.4 34'
        + '8.4L122.3 346L123.9 344.3L124.8 341.8L126.4 340.1L126.4 338.5L128.1 336.8L131.4 330.2L131.4 328.'
        + '5L134.8 322.7L134.8 320.2L137.2 316.9L137.2 314.4L138.1 313.5L138.9 307.7L140.6 304.4L139.7 278.'
        + '6L141.4 275.3L141.4 271.1L142.2 270.3L143.1 263.6L143.9 262.8L143.9 261.1L145.1 259.9L145.6 260.'
        + '3L145.6 262L146.4 262.8L146.4 267L147.2 267.8L148.1 273.6L149.7 276.9L149.7 281.1L150.6 281.9L15'
        + '0.6 287.8L151.4 288.6L151.4 291.9L153 295.2L152.2 296.1L153 296.9L153 300.2L152.2 301.1L152.2 30'
        + '4.4L151.4 305.2L151.4 307.7L150.6 308.5L149.7 314.4L148.1 317.7L148.1 321.8L147.2 322.7L147.2 32'
        + '6L146.4 326.8L146.4 342.6L145.6 343.5L145.6 348.4L144.7 349.3L144.7 351.8L143.1 354.3L143.1 356.'
        + '8L142.2 357.6L142.2 361.8L141.4 362.6L141.4 365.1L140.6 365.9L140.6 377.6L138.9 380.9L138.9 428.'
        + '3L139.7 429.1L139.7 436.6L140.6 437.4L140.6 441.6L141.4 442.4L141.4 445.7L142.2 446.6L143.1 459.'
        + '9L143.9 460.7L143.9 464.9L144.7 465.7L144.7 468.2L145.6 469L146.4 476.5L147.2 477.3L147.2 479.8L'
        + '148.1 480.7L148.1 483.1L148.9 484L148.9 488.1L149.7 489L149.7 491.5L150.6 492.3L151.4 496.4L153 '
        + '498.9L153.9 503.9L155.5 506.4L155.5 508.9L156.4 509.8L158 516.4L161.4 522.2L161.4 541.3L160.5 54'
        + '2.2L160.5 550.5L161.4 551.3L161.4 568L159.7 571.3L158.9 578.8L158 579.6L158 581.3L156.4 584.6L15'
        + '6.4 587.9L155.5 588.7L155.5 593.7L154.7 594.6L154.7 618.7L155.5 619.5L155.5 625.3L156.4 626.2L15'
        + '6.4 630.3L157.2 631.1L157.2 635.3L158 636.1L158 639.5L158.9 640.3L159.7 646.9L161.4 649.4L161.4 '
        + '652.8L163 656.1L163.9 661.9L165.5 664.4L166.3 668.6L168.8 673.6L168.8 676L169.7 676.9L170.5 681.'
        + '9L172.2 685.2L173 691.8L174.7 694.3L174.7 697.7L175.5 698.5L175.5 701L176.3 701.8L176.3 706.8L17'
        + '5.5 707.6L175.5 710.1L174.7 711L174.7 716.8L172.2 720.1L172.2 720.9L168.8 724.3L168.8 725.9L161.'
        + '8 733.8L157.6 735.5L156 737.2L151 739.7L146.4 744.2L146.4 745.1L143.1 747.6L143.1 753.4L143.9 75'
        + '4.2L143.9 756.7L148.1 764.2L150.1 766.3L154.3 766.3L156 767.9L159.3 768.8L160.1 769.6L166.8 769.'
        + '6L169.3 767.9L170.9 767.9L172.6 766.3L174.2 766.3L176.7 764.6L183.4 762.9L183.8 761.7L186.3 760L'
        + '186.3 759.2L192.5 750.5L195.9 749.6L199.2 747.1L201.7 747.1L205 745.5L207.5 745.5L210.4 742.6L21'
        + '0.8 741.3L212.5 741.3L213.7 744.2L218.3 748L220 748L222.5 749.6L225 749.6L225.8 750.5L229.1 751.'
        + '3L230.4 752.5L233.7 760L237.4 764.6L240.8 766.3L249.1 767.1L249.9 767.9L252.4 767.9L255.7 769.6L'
        + '261.6 769.6L261.6 767.9L264.9 768.8L265.7 767.9L267.4 767.9L269.9 766.3L273.2 765.4L275.3 763.3L'
        + '276.9 760L277.8 755L278.6 754.2L278.6 750.9L276.9 747.6L275.7 746.3L274.9 746.3L266.5 738L263.2 '
        + '738L254.5 729.3L254.5 727.6L249.5 721.8L249.5 720.1L247.8 717.6L247.8 716L246.2 714.3L246.2 711L'
        + '245.3 710.1L246.2 696L247 695.2L247 693.5L247.8 692.7L247.8 691L248.7 690.2L248.7 688.5L249.5 68'
        + '7.7L249.5 686L251.2 682.7L251.2 679.4L254.5 672.7L254.5 671.1L255.3 670.2L255.3 668.6L256.1 667.'
        + '7L256.1 666.1L257 665.2L257 663.6L258.6 660.2L258.6 656.9L259.5 656.1L260.3 651.9L262 649.4L262 '
        + '646.1L262.8 645.3L262.8 638.6L263.6 637.8L263.6 629.5L264.5 628.7L264.5 622.8L265.3 622L265.3 60'
        + '2L264.5 601.2L264.5 584.6L263.6 583.8L262.8 577.1L262 576.3L261.1 569.6L260.3 568.8L260.3 525.6L'
        + '261.1 524.7L261.1 521.4L262.8 519.7L262.8 518.1L264.5 514.7L266.1 513.1L266.1 510.6L269.4 503.9L'
        + '269.4 502.3L271.1 498.9L271.1 496.4L271.9 495.6L271.9 492.3L273.6 489.8L273.6 485.6L275.3 482.3L'
        + '275.3 464L276.1 463.2L276.1 456.5L276.9 455.7L276.9 449.9L277.8 449.1L277.8 440.7L278.6 439.9L27'
        + '8.6 436.6L279.4 435.8L279.4 422.4L280.3 421.6L280.3 385L279.4 384.2L279.4 367.6L278.6 366.7L277.'
        + '8 358.4L276.9 357.6L276.9 355.9L275.3 352.6L275.3 350.1L274.4 349.3L274.4 345.1L273.6 344.3L273.'
        + '6 330.2L272.8 329.3L271.9 322.7L271.1 321.8L271.1 319.3L270.3 318.5L270.3 316L269.4 315.2L269.4 '
        + '312.7L268.6 311.9L268.6 307.7L267.8 306.9L267.8 304.4L267 303.6L267 293.6L267.8 292.7L268.6 286.'
        + '9L270.3 283.6L270.3 281.1L271.9 277.8L271.9 275.3L272.8 274.4L272.8 272L273.6 271.1L273.6 268.6L'
        + '274.4 267L274.9 266.6L276.1 267.8L276.1 270.3L276.9 271.1L276.9 273.6L277.8 274.4L277.8 276.9L27'
        + '8.6 277.8L278.6 281.1L280.3 283.6L280.3 296.1L281.1 296.9L281.1 303.6L282.8 306.9L282.8 311L284.'
        + '4 313.5L284.4 316L286.1 319.3L286.1 321.8L286.9 322.7L286.9 324.3L288.6 326.8L288.6 328.5L291.1 '
        + '333.5L291.1 334.3L293.7 338.8L298 344.8L301.5 350.4L304.8 355L307.5 359.5L310.2 364L312.3 368.8L'
        + '315.1 374.8L317.4 378.5L319.5 383.1L322.1 388L326 393.9L326.4 400.3L326.5 405.5L326.3 411.1L326.'
        + '5 417.2L327.3 421.4L329.2 427.2L331 431.9L331.8 435.6L331.8 439.1L333.4 441.3L335.5 445.3L337.8 '
        + '449.3L339.7 454.5L342.2 454.5L344.3 452.4L344.7 449.5L348.4 454L348.4 456.5L350.1 458.2L350.1 45'
        + '9.9L354.7 463.6L357.2 462.8L359.2 460.7L359.2 459L360.5 457.8L361.7 460.7L363 461.1L363.8 462.8L'
        + '365.5 462.8L366.7 461.5L367.1 457.8L369.6 461.1L370.9 460.7L372.3 457.2L374 455.2L377.5 456.2L38'
        + '1.1 453.4L380.9 449.9L380.9 447.4L379.2 444.9L379.2 443.2L378.4 442.4L376.7 435.8L377 433.7L376.'
        + '2 429.3L375.9 427.4L374.6 422.8L372.6 419.1L370.8 415.9L369.2 410.8L380.3 420.2L383.3 416.5L381.'
        + '9 411.1L380.7 409L376.8 403.6L373.4 398.7L368.9 395.4L361.7 391.7L361.7 390L358.4 383.4L357.6 37'
        + '9.2L355.9 376.7L355.9 375.1L354.3 372.6L354.3 370.9L352.6 368.4L352.6 366.7L350.9 364.2L350.9 36'
        + '2.6L347.6 355.9L346.8 351.8L345.1 349.3L345.1 347.6L343.4 345.1L343.4 343.5L341.8 341L341.8 339.'
        + '3L340.1 336.8L340.1 335.1L337.6 334.3L337.6 325.2L336.8 324.3L336.8 320.2L335.1 316.9L335.1 314.'
        + '4L334.3 313.5L333.5 309.4L331.8 306.9L331.8 304.4L330.1 301.1L330.1 298.6L327.7 295.2L319.3 278.'
        + '6L318.5 274.4L316.8 273.6L316.8 271.1L315.2 268.6L315.2 261.1L314.3 260.3L315.2 258.7L314.3 257L'
        + '314.3 237L313.5 236.2L313.5 231.2L312.7 230.4L312.7 221.2L311.9 220.4L311.9 212.1L311 211.3L311 '
        + '188.8L310.2 188L309.4 176.3L308.5 175.5L308.5 173L307.7 172.2L306.9 166.4L305.2 163.9L305.2 162.'
        + '2L303.5 160.5L303.5 158L299 151L297.3 151L294 148.5L292.3 148.5L289.8 146.8L288.2 146.8L286.5 14'
        + '5.2L278.2 141L276.5 141L273.2 139.3L270.7 139.3L269.9 138.5L267.4 138.5L265.7 136.8L264 136.8L26'
        + '2.4 135.2L260.7 135.2L258.2 133.5L256.6 133.5L253.2 131.9L246.6 131L244.1 129.4L239.9 128.5L236.'
        + '6 126.9L233.7 122.3L233.7 119.8L232.9 119L232.9 110.7L234.5 109L236.2 105.7L236.2 103.2L237.9 10'
        + '0.7L237.9 99L239.5 96.5L239.5 94.9L244.5 90.7L244.5 89L247.8 83.2L247.8 81.6L249.5 78.2L249.8 71'
        + '.7L248.6 68.1L246.3 67.4L243.1 68.5L244.7 62.2L245.6 56.3L245.2 49.4L244.5 44L243.1 39.1ZM210 55'
        + '7.6L209.6 561.3L208.8 562.1L208.8 564.6L207.1 567.1L207.1 568.8L206.3 569.6L206.3 572.9L204.6 57'
        + '5.4L204.6 577.9L203.8 578.8L203.8 581.3L202.9 582.1L202.9 587.1L203.8 587.9L204.6 595.4L205.4 59'
        + '6.2L205.4 598.7L206.3 599.6L206.3 605.4L207.1 606.2L207.1 628.7L206.3 629.5L205.4 639.5L204.6 64'
        + '0.3L204.6 693.5L205.4 694.3L205.4 699.3L206.3 700.2L206.3 706.8L207.1 707.6L207.1 714.3L206.3 71'
        + '5.1L206.3 719.3L207.1 720.1L207.1 722.6L207.9 723.4L208.8 727.6L210.4 730.1L210.4 731.8L211.7 73'
        + '2.2L213.7 729.3L213.7 725.9L215.4 722.6L215.4 698.5L216.2 697.7L216.2 693.5L217.1 692.7L217.1 64'
        + '0.3L216.2 639.5L215.4 627L214.6 626.2L214.6 622.8L213.7 622L213.7 612.9L214.6 612L214.6 606.2L21'
        + '5.4 605.4L215.4 593.7L216.2 592.9L216.2 590.4L217.1 589.6L217.1 582.1L216.2 581.3L216.2 578.8L21'
        + '5.4 577.9L215.4 574.6L213.7 572.1L213.7 568.8L212.1 565.5L211.2 558Z';

    var BODY_SVG =
        '<defs>' +
            '<path id="mer-body-shape" fill-rule="evenodd" d="' + BODY_OUTLINE_D + '"/>' +
        '</defs>' +
        '<g class="mer-body">' +
            '<use href="#mer-body-shape" class="mer-fill"/>' +
            '<use href="#mer-body-shape" class="mer-line"/>' +
        '</g>';

    // 各脉自己的附加轮廓，按脉络 id 分键（当前只有督脉：把头段照抄一份平移到身体右侧，
    // 单独闭合、与本体不相连，用来承接绕头的 12 个穴位，避免标注全挤在颈部）。
    // 只有选中脉络命中键时才渲染；一条脉的附加块不影响其他脉。编辑器写回这一句。
    var MER_EXTRA_OUTLINE_D = {
        du: 'M351.7 122.3L351.7 119.8L350.9 119L350.9 110.7L352.5 109L354.2 105.7L354.2 103.2L355.9 100.7L355'
            + '.9 99L357.5 96.5L357.5 94.9L362.5 90.7L362.5 89L365.8 83.2L365.8 81.6L367.5 78.2L367.8 71.7L366.'
            + '6 68.1L364.3 67.4L361.1 68.5L362.7 62.2L363.6 56.3L363.2 49.4L362.5 44L361.1 39.1L358 34.6L355.6'
            + ' 32.1L352.9 29.6L350.2 27.6L347.9 25.7L343.8 23.7L339 22.4L333.2 21.2L325 20.6L316.2 22L309.9 23'
            + '.9L304.6 26.5L301.2 29.3L297.9 32.5L294.2 37.3L292 42.6L290.6 50.4L290.3 57.5L291.7 67.3L289.8 6'
            + '5.3L288.9 66.2L287.3 66.2L285.2 70.7L285.2 74.1L286 74.9L286.8 79.9L289.3 84.9L290.2 89L291 90.7'
            + 'L293.9 93.6L295.2 94L296 95.7L296 98.2L296.8 99L296.8 101.5L298.5 104L298.5 105.7L301.8 109.8L30'
            + '1.8 120.6L301 121.5L301 124Z'
    };

    // 每条脉的穴位示意坐标（顺序与连线同 meridians_config.json 的节点），键与配置 id 对齐。
    // 任脉/督脉按参考图实测点距分段映射到本图解剖标志（下巴/胸骨上窝/剑突/脐/耻骨联合/裆），
    // 督脉头后段（哑门→后顶）左偏 20px 表示"绕到脑后"；中线穴标签由 buildMapSvg 按序号左右交错。
    var NODE_LAYOUT = {
        ren:      [[211, 556], [211, 550], [211, 531], [211, 512], [212, 494], [211, 484], [211, 474], [210, 456], [209, 432], [210, 411], [210, 369], [210, 349], [210, 328], [210, 305], [210, 284], [211, 260], [209, 235], [210, 210], [209, 183], [210, 158], [210, 135], [209, 120], [209, 108]],
        du:       [[210, 555], [211, 540], [211, 482], [209, 433], [210, 397], [210, 377], [210, 352], [210, 302], [211, 278], [211, 252], [209, 198], [210, 155], [210, 135], [210, 109.6], [210, 95.3], [209.1, 82], [209.1, 64.2], [210, 49.9], [210, 33], [326.3, 36.7], [326.3, 43.7], [326.3, 50.7], [326.3, 57.7], [326.3, 64.7], [326.3, 86.7], [326.3, 93.7], [325.3, 100.7]],
        chong:    [[224, 460], [224, 448], [224, 437], [224, 426], [224, 415], [224, 404], [224, 391], [224, 378], [224, 365], [224, 352], [224, 340], [224, 324], [224, 308], [224, 293], [224, 278], [224, 264], [224, 250]],
        dai:      [[160, 302], [262, 318], [266, 336], [268, 424], [262, 440], [172, 452]],
        yinwei:   [[226, 620], [226, 588], [196, 470], [186, 462], [190, 452], [182, 400], [184, 366], [190, 316], [202, 326], [198, 258]],
        yangwei:  [[244, 722], [232, 660], [234, 634], [236, 548], [258, 458], [262, 424], [268, 208], [276, 182], [222, 152], [228, 136]],
        yinqiao:  [[234, 748], [232, 716], [230, 682], [228, 618], [226, 556], [224, 500], [212, 256], [198, 148]],
        yangqiao: [[262, 748], [250, 728], [240, 698], [262, 636], [250, 548], [266, 458], [272, 424], [264, 336], [284, 210], [292, 194], [304, 174], [296, 156], [240, 138], [226, 150]]
    };

    // 穴位标注外观（单位＝缩放 1 时的屏幕像素，放大时自动反算，故屏幕上恒定）：
    // 字号 / 同列最小行距 / 标签列与最外穴位的间距 / 穴位圆点半径
    var LABEL_FONT = 20, LABEL_GAP = 27, LABEL_COL = 15, DOT_R = 7;

    var ZOOM_MIN = 0.6;    var ZOOM_MAX = 4;
    var ZOOM_STEP = 1.25;

    var _el, _refs;
    var _reqSeq = 0;
    var _pending = {};
    var _meridians = [];
    var _lit = {};
    var _kpoint = 0;
    var _infoValues = {};
    // 四类收益预算（AS2 权威回包的 bonusCaps / bonusUsed / bonusApplied），按收益类型分别记账。
    // 健身房把 HP/MP 上限与防御的练级空间让出一半给穴位，内力则只搬来原上限的一半，故预算分四类互不挪用。
    var BONUS_SPECS = [
        {key: 'innerPower', label: '内力'},
        {key: 'hp', label: 'HP上限'},
        {key: 'mp', label: 'MP上限'},
        {key: 'defense', label: '防御'}
    ];
    var _caps = {};   // 该类型预算上限
    var _used = {};   // 已点亮穴位的原始累加值（未截断）
    var _applied = {}; // 实际计入角色的值（按预算截断后）
    var _selectedIndex = 0;
    var _selectedNode = null;
    var _requireKey = null;   // 右栏情报清单的内容签名，内容没变就不重建 DOM
    var _busyNodes = {};
    var _projection = null;
    var _scaleHandle = null;
    var _panelInstanceId = '';
    var _zoom = 1, _panX = 0, _panY = 0;
    var _dragging = false, _dragMoved = false, _dragX = 0, _dragY = 0;

    Panels.register('meridians', {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        onRequestClose: doClose
    });

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'meridians') return;
        var request = _pending[data.callId];
        if (!request) return;
        delete _pending[data.callId];
        request.callback(data);
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'meridians-panel';
        _el.setAttribute('data-workbench-skin', 'archive');
        _el.innerHTML =
            '<div class="mer-shell">' +
                '<header class="mer-header">' +
                    '<div class="mer-heading">' +
                        '<div class="mer-title">经脉</div>' +
                        '<div class="mer-subtitle">体内 θ-域耦合通道 · 以情报为引，K 点贯注</div>' +
                    '</div>' +
                    '<div class="mer-budgets"></div>' +
                    '<div class="mer-kpoint-box">' +
                        '<div class="mer-kpoint-label">K点</div>' +
                        '<div class="mer-kpoint-value">0</div>' +
                    '</div>' +
                    '<button class="mer-close-btn" type="button" title="关闭" aria-label="关闭"></button>' +
                '</header>' +
                '<aside class="mer-catalog" aria-label="经脉目录">' +
                    '<div class="mer-catalog-list"></div>' +
                '</aside>' +
                '<main class="mer-reader">' +
                    '<section class="mer-map-col" aria-label="人体经脉图">' +
                        '<div class="mer-status">正在读取经脉状态…</div>' +
                        '<div class="mer-map">' +
                            '<div class="mer-zoom-viewport"><div class="mer-canvas"></div></div>' +
                            '<div class="mer-zoom-bar">' +
                                '<button class="mer-zoom-btn" type="button" data-zoom="in" title="放大">＋</button>' +
                                '<button class="mer-zoom-btn" type="button" data-zoom="out" title="缩小">－</button>' +
                                '<button class="mer-zoom-btn" type="button" data-zoom="reset" title="复位">↺</button>' +
                            '</div>' +
                        '</div>' +
                        '<div class="mer-node-bar" role="group" aria-label="选中穴位"></div>' +
                        '<div class="mer-legend">' +
                            '<span class="mer-legend-item mer-legend-body">人体轮廓</span>' +
                            '<span class="mer-legend-item mer-legend-white">未贯通</span>' +
                            '<span class="mer-legend-item mer-legend-next">下一穴</span>' +
                            '<span class="mer-legend-item mer-legend-sealed">按序未到</span>' +
                            '<span class="mer-legend-item mer-legend-green">已贯通</span>' +
                            '<span class="mer-legend-hint">滚轮缩放 · 拖拽平移 · 点击穴位选择</span>' +
                        '</div>' +
                    '</section>' +
                    '<section class="mer-side">' +
                        '<div class="mer-meridian-head">' +
                            '<div class="mer-meridian-name"></div>' +
                            '<div class="mer-meridian-desc"></div>' +
                            '<div class="mer-meridian-progress"></div>' +
                            '<div class="mer-require-list"></div>' +
                        '</div>' +
                        '<div class="mer-action" role="group" aria-label="穴位贯注"></div>' +
                    '</section>' +
                '</main>' +
                '<footer class="mer-footer">' +
                    '<div class="mer-error" aria-live="polite"></div>' +
                '</footer>' +
            '</div>';
        buildBudgetBoxes();
        collectRefs();
        return _el;
    }

    // 表头的四类预算框：标签由 BONUS_SPECS 固定，数值只认 AS2 回包。
    function buildBudgetBoxes() {
        var holder = _el.querySelector('.mer-budgets');
        for (var i = 0; i < BONUS_SPECS.length; i++) {
            var box = document.createElement('div');
            box.className = 'mer-total-box';
            box.setAttribute('data-stat', BONUS_SPECS[i].key);
            var label = document.createElement('div');
            label.className = 'mer-total-label';
            label.textContent = BONUS_SPECS[i].label;
            var value = document.createElement('div');
            value.className = 'mer-total-value';
            value.textContent = '+0 / 0';
            box.appendChild(label);
            box.appendChild(value);
            holder.appendChild(box);
        }
    }

    // 预算框由 createDOM 生成，这里按 data-stat 取回数值节点，渲染时逐类型写入。
    function collectBudgetValues() {
        var values = {};
        var boxes = _el.querySelectorAll('.mer-budgets .mer-total-box');
        for (var i = 0; i < boxes.length; i++) {
            values[boxes[i].getAttribute('data-stat')] = boxes[i].querySelector('.mer-total-value');
        }
        return values;
    }

    // 四类预算只认 AS2 回包；缺字段按 0 计，Web 不自带上限。
    function readBonusMap(source) {
        var map = {};
        for (var i = 0; i < BONUS_SPECS.length; i++) {
            var key = BONUS_SPECS[i].key;
            var value = Number(source && source[key]);
            map[key] = isFinite(value) ? value : 0;
        }
        return map;
    }

    function applyBonusSnapshot(resp) {
        _caps = readBonusMap(resp.bonusCaps);
        _used = readBonusMap(resp.bonusUsed);
        _applied = readBonusMap(resp.bonusApplied);
    }

    function bonusLabelOf(bonusType) {
        for (var i = 0; i < BONUS_SPECS.length; i++) {
            if (BONUS_SPECS[i].key === bonusType) return BONUS_SPECS[i].label;
        }
        return BONUS_SPECS[0].label;
    }

    function bonusTypeOf(node) {
        return (node && node.bonusType) || BONUS_SPECS[0].key;
    }

    function bonusAmountOf(node) {
        var amount = Number(node && node.bonusAmount);
        return isFinite(amount) ? amount : 0;
    }

    // 回包没带收益类型时（旧版 AS2 或缓存重放），退回当前选中穴位的类型。
    function selectedBonusType() {
        var meridian = _meridians[_selectedIndex];
        var index = nodeIndexOf(meridian, _selectedNode);
        if (index < 0) return BONUS_SPECS[0].key;
        return bonusTypeOf((meridian.nodes || [])[index]);
    }

    function collectRefs() {
        _refs = {
            shell: _el.querySelector('.mer-shell'),
            status: _el.querySelector('.mer-status'),
            budgetValues: collectBudgetValues(),
            kpointValue: _el.querySelector('.mer-kpoint-value'),
            catalogList: _el.querySelector('.mer-catalog-list'),
            viewport: _el.querySelector('.mer-zoom-viewport'),
            canvas: _el.querySelector('.mer-canvas'),
            zoomBar: _el.querySelector('.mer-zoom-bar'),
            meridianName: _el.querySelector('.mer-meridian-name'),
            meridianDesc: _el.querySelector('.mer-meridian-desc'),
            meridianProgress: _el.querySelector('.mer-meridian-progress'),
            requireList: _el.querySelector('.mer-require-list'),
            nodeBar: _el.querySelector('.mer-node-bar'),
            action: _el.querySelector('.mer-action'),
            error: _el.querySelector('.mer-error'),
            closeBtn: _el.querySelector('.mer-close-btn')
        };
        _refs.closeBtn.addEventListener('click', doClose);
        // 穴位点击走画布代理：SVG 每次 renderMap 重建，无需逐点重挂监听。
        _refs.canvas.addEventListener('click', function(ev) {
            if (_dragMoved) return;
            var target = ev.target;
            var nodeId = target && target.getAttribute
                ? target.getAttribute('data-node') : null;
            if (!nodeId) return;
            selectNode(nodeId);
        });
        _refs.zoomBar.addEventListener('click', function(ev) {
            var target = ev.target;
            var op = target && target.getAttribute
                ? target.getAttribute('data-zoom') : null;
            if (!op) return;
            if (op === 'reset') resetView();
            else zoomAt(op === 'in' ? ZOOM_STEP : 1 / ZOOM_STEP,
                _refs.viewport.clientWidth / 2, _refs.viewport.clientHeight / 2);
        });
        _refs.viewport.addEventListener('wheel', function(ev) {
            ev.preventDefault();
            var rect = _refs.viewport.getBoundingClientRect();
            var k = rect.width > 0 ? _refs.viewport.clientWidth / rect.width : 1;
            zoomAt(ev.deltaY < 0 ? 1.15 : 1 / 1.15,
                (ev.clientX - rect.left) * k, (ev.clientY - rect.top) * k);
        }, { passive: false });
        _refs.viewport.addEventListener('pointerdown', function(ev) {
            if (ev.button !== 0) return;
            _dragging = true;
            _dragMoved = false;
            _dragX = ev.clientX;
            _dragY = ev.clientY;
            _refs.viewport.classList.add('is-panning');
        });
        _refs.viewport.addEventListener('pointermove', function(ev) {
            if (!_dragging) return;
            var rect = _refs.viewport.getBoundingClientRect();
            var k = rect.width > 0 ? _refs.viewport.clientWidth / rect.width : 1;
            var dx = (ev.clientX - _dragX) * k;
            var dy = (ev.clientY - _dragY) * k;
            if (Math.abs(dx) + Math.abs(dy) > 2) _dragMoved = true;
            _panX += dx;
            _panY += dy;
            _dragX = ev.clientX;
            _dragY = ev.clientY;
            applyView();
        });
        var endPan = function() {
            _dragging = false;
            _refs.viewport.classList.remove('is-panning');
        };
        _refs.viewport.addEventListener('pointerup', endPan);
        _refs.viewport.addEventListener('pointerleave', endPan);
    }

    // ── 缩放/平移视图 ──

    // 平移只写 transform 的 translate（pointermove 每帧都走，不碰缩放的自定义属性）。
    function applyView() {
        var r3 = function(v) { return Math.round(v * 1000) / 1000; };
        _refs.canvas.style.transform =
            'translate(' + r3(_panX) + 'px, ' + r3(_panY) + 'px)';
    }

    // 缩放不用 transform scale：合成层带 scale 会把已栅格化的位图整体拉伸，放大后穴位标签就糊了。
    // 改成按 --mer-zoom 撑开 SVG 布局尺寸，文字与轮廓走矢量重栅格，任何倍率都锐利。
    function applyZoomSize() {
        _refs.canvas.style.setProperty('--mer-zoom',
            Math.round(_zoom * 1000) / 1000);
    }

    // 横轴上 SVG 由 flex 居中，尺寸从视口中心向外长；纵轴顶对齐，从顶边向下长。
    // 保持光标下的内容点不动：pan' = u - (u - pan) * (z'/z)，u 是该轴相对缩放原点的偏移。
    function zoomAt(factor, cx, cy) {
        var next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, _zoom * factor));
        if (next === _zoom) return;
        var ratio = next / _zoom;
        var ux = cx - _refs.viewport.clientWidth / 2;
        _panX = ux - (ux - _panX) * ratio;
        _panY = cy - (cy - _panY) * ratio;
        _zoom = next;
        applyZoomSize();
        applyView();
        renderMap(); // 点位与文字要按新缩放反算，尺寸才不随缩放变化
    }

    function resetView() {
        _zoom = 1;
        _panX = 0;
        _panY = 0;
        applyZoomSize();
        applyView();
        renderMap();
    }

    function selectNode(nodeId) {
        for (var i = 0; i < _meridians.length; i++) {
            var nodes = _meridians[i].nodes || [];
            for (var n = 0; n < nodes.length; n++) {
                if (nodes[n].id === nodeId) {
                    _selectedIndex = i;
                    _selectedNode = nodeId;
                    renderAll();
                    return;
                }
            }
        }
    }

    function onOpen(el, initData) {
        _meridians = [];
        _lit = {};
        _selectedIndex = 0;
        _selectedNode = null;
        _requireKey = null;
        _busyNodes = {};
        _projection = null;
        resetView();
        showStatus('正在读取经脉状态…');
        showError('');

        initData = initData || {};
        _panelInstanceId = typeof initData.panelInstanceId === 'string'
            ? initData.panelInstanceId : '';
        _scaleHandle = (typeof PanelScale !== 'undefined' && PanelScale && PanelScale.attach)
            ? PanelScale.attach(_refs.shell, DESIGN_WIDTH, DESIGN_HEIGHT)
            : null;
        requestState();
    }

    function onClose() {
        if (_scaleHandle && _scaleHandle.detach) _scaleHandle.detach();
        _scaleHandle = null;
        _pending = {};
        _panelInstanceId = '';
    }

    // 本地清理先要留存本次 open 绑定的实例身份，再隐藏 DOM，最后把 close 信封交回宿主：
    // 宿主的撤幕/HUD 恢复/解除暂停都挂在这条 exact close 上，缺信封就是黑屏。
    function doClose() {
        var instance = _panelInstanceId;
        if (window.BootstrapAudio) window.BootstrapAudio.cue('back');
        Panels.close();
        Bridge.send({ type: 'panel', cmd: 'close', panel: 'meridians',
            panelInstanceId: instance });
    }

    // ========== 与 AS2 权威往返 ==========

    function sendRequest(cmd, payload, cb) {
        var callId = 'mer-' + (++_reqSeq);
        _pending[callId] = {
            cmd: String(cmd || ''),
            callback: typeof cb === 'function' ? cb : function() {}
        };
        var msg = payload || {};
        msg.type = 'panel';
        msg.panel = 'meridians';
        msg.cmd = cmd;
        msg.callId = callId;
        Bridge.send(msg);
    }

    function requestState() {
        sendRequest('state', {}, function(resp) {
            if (!resp || resp.success !== true) {
                showStatus('经脉数据暂不可用，稍后再试。');
                return;
            }
            applyState(resp);
            showStatus('');
        });
    }

    function applyState(resp) {
        adoptProjection(resp.projection);
        _meridians = resp.meridians || [];
        _lit = resp.lit || {};
        _kpoint = Number(resp.kpoint) || 0;
        _infoValues = resp.infoValues || {};
        applyBonusSnapshot(resp);
        if (_selectedIndex >= _meridians.length) _selectedIndex = 0;
        if (!_selectedNode && _meridians.length) {
            _selectedNode = autoSelectNode(_meridians[_selectedIndex]);
        }
        renderAll();
    }

    function lightNode(nodeId) {
        if (needsProjectionRecovery()) { requestState(); return; }
        if (_busyNodes[nodeId]) return;
        _busyNodes[nodeId] = true;
        sendRequest('light', { nodeId: nodeId }, function(resp) {
            delete _busyNodes[nodeId];
            if (resp && resp.applied === true) {
                adoptProjection(resp.projection);
                _lit[nodeId] = true;
                applyBonusSnapshot(resp);
                _kpoint = Number(resp.kpoint);
                var current = _meridians[_selectedIndex];
                if (current && _selectedNode === nodeId) {
                    // 贯完自动跟随到下一穴：栏位已取消，靠动作条连续贯注
                    _selectedNode = autoSelectNode(current);
                }
                if (resp.savePending === true) {
                    showError('已贯通，存档写入结果未确认；请勿重复点亮，稍后重开面板核对。');
                } else if (needsProjectionRecovery()) {
                    showError('已贯通，角色属性尚未更新；请重试属性更新。不会再次扣除 K 点。');
                } else {
                    showError('');
                }
                renderAll();
                return;
            }
            showError(lightFailureText(resp));
            renderAll();
        });
    }

    function lightFailureText(resp) {
        if (!resp) return '经脉贯注没有回音，请重试。';
        var code = String(resp.error || '');
        if (code === 'insufficient_funds') return 'K点不足，无法贯注此节点。';
        if (code === 'info_missing') {
            var names = resp.missingInfo || [];
            return names.length ? '仍缺情报：' + names.join('、') : '情报尚未集齐，此脉未解锁。';
        }
        if (code === 'already_lit') return '此穴位已贯通。';
        if (code === 'order_locked') {
            return resp.lockedBy ? '需先贯通「' + resp.lockedBy + '」。' : '此穴按脉序尚未解锁。';
        }
        if (code === 'node_info_missing') {
            var nodeNames = resp.missingInfo || [];
            return nodeNames.length ? '此穴仍缺情报：' + nodeNames.join('、') : '此穴所需情报尚未持有。';
        }
        if (code === 'bonus_cap_reached') {
            var stat = String(resp.bonusType || selectedBonusType());
            return bonusLabelOf(stat) + '预算已满（' + formatNumber(_used[stat] || 0)
                + ' / ' + formatNumber(_caps[stat] || 0) + '），无需再贯注。';
        }
        if (code === 'save_unavailable' || code === 'save_pending') return '存档系统暂不可用，本次贯注未生效。';
        if (code === 'config_unavailable' || code === 'node_unknown') return '经脉数据暂不可用。';
        return '贯注失败，请稍后重试。';
    }

    // ========== 渲染 ==========

    function renderAll() {
        renderHeaderNumbers();
        renderCatalog();
        renderReader();
        renderNodeBar();
        renderAction();
        renderMap();
    }

    function renderHeaderNumbers() {
        // 预算与累加值只认 AS2 回包，Web 不自行判定上限。
        for (var i = 0; i < BONUS_SPECS.length; i++) {
            var key = BONUS_SPECS[i].key;
            var valueEl = _refs.budgetValues[key];
            if (!valueEl) continue;
            valueEl.textContent = '+' + formatNumber(_applied[key] || 0)
                + ' / ' + formatNumber(_caps[key] || 0);
        }
        _refs.kpointValue.textContent = formatNumber(_kpoint);
    }

    function renderCatalog() {
        _refs.catalogList.innerHTML = '';
        for (var i = 0; i < _meridians.length; i++) {
            _refs.catalogList.appendChild(buildCatalogItem(_meridians[i], i));
        }
    }

    function buildCatalogItem(meridian, index) {
        var item = document.createElement('button');
        item.type = 'button';
        item.className = 'mer-catalog-item' + (index === _selectedIndex ? ' active' : '');
        var unlocked = meridianUnlocked(meridian);
        var litCount = 0;
        var nodes = meridian.nodes || [];
        for (var n = 0; n < nodes.length; n++) {
            if (_lit[nodes[n].id]) litCount++;
        }
        var head = document.createElement('div');
        head.className = 'mer-catalog-name';
        head.textContent = meridian.name || meridian.id;
        var meta = document.createElement('div');
        meta.className = 'mer-catalog-meta';
        meta.textContent = unlocked
            ? litCount + '/' + nodes.length + ' · ' + meridianBonusLabels(meridian)
            : '未解锁';
        if (!unlocked) meta.className += ' is-locked';
        item.appendChild(head);
        item.appendChild(meta);
        item.addEventListener('click', function() {
            _selectedIndex = index;
            _selectedNode = autoSelectNode(meridian);
            renderAll();
        });
        return item;
    }

    // 目录行标出本脉发的是哪类收益：按脉络绑定时只有一项，日后混配则并列显示。
    function meridianBonusLabels(meridian) {
        var labels = [];
        var nodes = meridian.nodes || [];
        for (var n = 0; n < nodes.length; n++) {
            var label = bonusLabelOf(bonusTypeOf(nodes[n]));
            if (labels.indexOf(label) < 0) labels.push(label);
        }
        return labels.join('·');
    }

    // 穴卡片栏去掉后，选脉即定位到本脉第一处未贯通的穴（全通则停在首穴），
    // 动作条一进来就有内容，玩家不必逐个点穴位去试。
    function autoSelectNode(meridian) {
        var nodes = (meridian && meridian.nodes) || [];
        for (var n = 0; n < nodes.length; n++) {
            if (!_lit[nodes[n].id]) return nodes[n].id;
        }
        return nodes.length ? nodes[0].id : null;
    }

    function renderReader() {
        var meridian = _meridians[_selectedIndex];
        _refs.meridianName.textContent = meridian ? (meridian.name || meridian.id) : '';
        _refs.meridianDesc.textContent = meridian ? (meridian.desc || '') : '';
        _refs.meridianProgress.textContent = meridian ? progressText(meridian) : '';
        if (!meridian) {
            if (!_refs.status.textContent) showStatus('经脉数据为空。');
        }
        renderRequireList(meridian, selectedNode(meridian));
    }

    // 右栏只留介绍与情报提示：本脉进度与按序说明用一行文字交代，不再出穴位栏位。
    function progressText(meridian) {
        var nodes = meridian.nodes || [];
        var litCount = 0;
        for (var n = 0; n < nodes.length; n++) {
            if (_lit[nodes[n].id]) litCount++;
        }
        var text = '已贯通 ' + litCount + ' / ' + nodes.length + ' 穴';
        if (litCount >= nodes.length) return text + ' · 本脉已尽数贯通。';
        return text + ' · 同脉按顺序贯注，前一穴通了才通下一穴。';
    }

    // 情报清单一物一行。清单内容按「脉 + 当前选中穴 + 各物是否已持有」签名，
    // 贯注后签名没变就不重建 DOM——清单没换东西却闪一下会打断连续贯注的节奏。
    function renderRequireList(meridian, node) {
        var required = requireItemsFor(meridian, node);
        var key = meridian ? String(meridian.id) : '';
        for (var i = 0; i < required.length; i++) {
            key += '|' + required[i] + (holdsInfo(required[i]) ? '=' : '-');
        }
        if (key === _requireKey) return;
        _requireKey = key;
        _refs.requireList.innerHTML = '';
        for (i = 0; i < required.length; i++) {
            var chip = document.createElement('span');
            var held = holdsInfo(required[i]);
            chip.className = 'mer-require-chip' + (held ? ' is-held' : ' is-missing');
            chip.textContent = (held ? '✓ ' : '✗ ') + required[i];
            _refs.requireList.appendChild(chip);
        }
    }

    function holdsInfo(name) {
        return (Number(_infoValues[name]) || 0) > 0;
    }

    // 脉级情报是解锁门槛，穴级情报（配置里还没赋值，只留接口）叠加在其后。
    function requireItemsFor(meridian, node) {
        var out = [];
        var sources = [
            (meridian && meridian.requiredInfo) || [],
            (node && node.requiredInfo) || []
        ];
        for (var s = 0; s < sources.length; s++) {
            for (var r = 0; r < sources[s].length; r++) {
                if (out.indexOf(sources[s][r]) < 0) out.push(sources[s][r]);
            }
        }
        return out;
    }

    function selectedNode(meridian) {
        var index = meridian && _selectedNode ? nodeIndexOf(meridian, _selectedNode) : -1;
        return index >= 0 ? meridian.nodes[index] : null;
    }

    // ── 图下动作条：只交代选中穴是谁、给什么、多少钱；贯注按钮在右栏底部 ──
    // 门槛判定全在 AS2（MeridianPanelService.executeLight），这里只按权威回包呈现原因。

    function nodeIndexOf(meridian, nodeId) {
        var nodes = (meridian && meridian.nodes) || [];
        for (var n = 0; n < nodes.length; n++) {
            if (nodes[n].id === nodeId) return n;
        }
        return -1;
    }

    /** 穴位状态：lit 已贯通 / next 可贯注 / sealed 按序未到 / info 情报不足 / capped 预算已满 */
    function nodeState(meridian, index) {
        var nodes = (meridian && meridian.nodes) || [];
        var node = nodes[index];
        if (!node) return 'sealed';
        if (_lit[node.id]) return 'lit';
        if (!meridianUnlocked(meridian)) return 'info';
        if (index > 0 && !_lit[nodes[index - 1].id]) return 'sealed';
        if (missingNodeInfo(node)) return 'info';
        // 预算门槛按穴位自己的收益类型判定，与 AS2 executeLight 同口径。
        var stat = bonusTypeOf(node);
        if ((_used[stat] || 0) + bonusAmountOf(node) > (_caps[stat] || 0)) return 'capped';
        return 'next';
    }

    // 穴级情报需求：配置里 node.requiredInfo 还没分配，接口先留着，作者以后改 JSON 即生效。
    function missingNodeInfo(node) {
        var required = (node && node.requiredInfo) || [];
        for (var r = 0; r < required.length; r++) {
            if (!holdsInfo(required[r])) return required[r];
        }
        return null;
    }

    function nodeStateText(meridian, index, state) {
        var nodes = (meridian && meridian.nodes) || [];
        if (state === 'lit') return '已贯通';
        if (state === 'info') {
            if (meridianUnlocked(meridian)) {
                return '缺少情报「' + missingNodeInfo(nodes[index]) + '」';
            }
            return '情报未集齐，此脉未解锁';
        }
        if (state === 'capped') {
            var stat = bonusTypeOf(nodes[index]);
            return bonusLabelOf(stat) + '预算已满（' + formatNumber(_used[stat] || 0)
                + ' / ' + formatNumber(_caps[stat] || 0) + '）';
        }
        if (state === 'sealed' && index > 0) {
            var prev = nodes[index - 1];
            return '需先贯通「' + (prev ? prev.name || prev.id : '') + '」';
        }
        return '按序未到';
    }

    function renderNodeBar() {
        var bar = _refs.nodeBar;
        bar.innerHTML = '';
        var meridian = _meridians[_selectedIndex];
        var index = meridian && _selectedNode ? nodeIndexOf(meridian, _selectedNode) : -1;
        var node = index >= 0 ? meridian.nodes[index] : null;
        bar.className = 'mer-node-bar' + (node ? ' is-' + nodeState(meridian, index) : ' is-empty');
        if (!node) {
            var tip = document.createElement('div');
            tip.className = 'mer-bar-hint';
            tip.textContent = '点击图上穴位选择要贯注的穴。';
            bar.appendChild(tip);
            return;
        }
        var cost = Number(node.cost) || 0;

        var name = document.createElement('div');
        name.className = 'mer-bar-name';
        name.textContent = (meridian.name || meridian.id) + '·' + (node.name || node.id);
        var gain = document.createElement('div');
        gain.className = 'mer-bar-gain';
        gain.textContent = bonusLabelOf(bonusTypeOf(node)) + ' +' + formatNumber(bonusAmountOf(node));
        var costText = document.createElement('div');
        costText.className = 'mer-bar-cost';
        costText.textContent = formatNumber(cost) + ' K';

        bar.appendChild(name);
        bar.appendChild(gain);
        bar.appendChild(costText);
    }

    // ── 右栏底部贯注区：状态原因 + 唯一贯注按钮 ──

    function renderAction() {
        var box = _refs.action;
        box.innerHTML = '';
        var meridian = _meridians[_selectedIndex];
        var index = meridian && _selectedNode ? nodeIndexOf(meridian, _selectedNode) : -1;
        var node = index >= 0 ? meridian.nodes[index] : null;
        box.className = 'mer-action' + (node ? ' is-' + nodeState(meridian, index) : ' is-empty');
        if (needsProjectionRecovery()) {
            var recoveryHint = document.createElement('div');
            recoveryHint.className = 'mer-action-state';
            recoveryHint.textContent = '已点亮的节点保持生效记录；角色属性待更新。';
            var recoveryButton = document.createElement('button');
            recoveryButton.type = 'button'; recoveryButton.className = 'mer-action-btn';
            recoveryButton.textContent = '重试属性更新';
            recoveryButton.addEventListener('click', requestState);
            box.appendChild(recoveryHint); box.appendChild(recoveryButton); return;
        }
        if (!node) return;
        var state = nodeState(meridian, index);
        var busy = !!_busyNodes[node.id];
        var affordable = _kpoint >= (Number(node.cost) || 0);

        var hint = document.createElement('div');
        hint.className = 'mer-action-state';
        hint.textContent = busy ? '贯注中…'
            : (state === 'next' ? (affordable ? '可贯注' : 'K点不足') : nodeStateText(meridian, index, state));

        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'mer-action-btn';
        btn.textContent = state === 'lit' ? '已贯通' : '贯注';
        btn.disabled = state !== 'next' || !affordable || busy;
        btn.addEventListener('click', function() { lightNode(node.id); });

        box.appendChild(hint);
        box.appendChild(btn);
    }

    function meridianUnlocked(meridian) {
        var required = (meridian && meridian.requiredInfo) || [];
        for (var r = 0; r < required.length; r++) {
            if (!holdsInfo(required[r])) return false;
        }
        return true;
    }
    function adoptProjection(value) {
        var valid = value && typeof value === 'object' && !Array.isArray(value)
            && Object.keys(value).sort().join('|') === 'reason|status'
            && ['applied', 'unchanged', 'pending', 'failed'].indexOf(value.status) >= 0
            && typeof value.reason === 'string' && value.reason.length <= 160;
        _projection = valid ? {status:value.status, reason:value.reason}
            : {status:'failed', reason:'projection_status_unavailable'};
    }
    function needsProjectionRecovery() {
        return _projection && (_projection.status === 'failed'
            || _projection.status === 'pending' && _projection.reason !== 'pending_actor');
    }

    // ── 人体经脉图：蓝轮廓 / 白未贯通 / 绿已贯通，选中脉高亮 ──

    function renderMap() {
        if (!_refs.canvas) return;
        _refs.canvas.innerHTML = buildMapSvg();
    }

    // 缩放由 SVG 自身的布局尺寸施加（见 applyZoomSize），所以点位、连线和文字一律按 1/zoom 反缩放：
    // 屏幕上尺寸恒定，放大只是把身体撑开，让原本挤在一起的穴位自然分开。
    // 标签分左右两列各自排布，保持最小屏幕行距；被推开的标签用引线连回穴位。
    function buildMapSvg() {
        var k = 1 / _zoom;
        var q = function(v) { return Math.round(v * 100) / 100; };
        var parts = ['<svg class="mer-svg" viewBox="0 0 420 780" role="img" aria-label="人体经脉示意图">'];
        parts.push('<g class="mer-body">' + BODY_SVG + '</g>');
        // 只画当前选中脉的穴位与连线：八脉同屏会互相压线、难以辨认（作者要求）
        var meridian = _meridians[_selectedIndex];
        var extraD = meridian && MER_EXTRA_OUTLINE_D[meridian.id];
        if (extraD) {
            parts.push('<g class="mer-body"><path class="mer-fill" d="' + extraD + '"/>'
                + '<path class="mer-line" d="' + extraD + '"/></g>');
        }
        if (meridian) {
            var layout = NODE_LAYOUT[meridian.id];
            var nodes = meridian.nodes || [];
            if (layout && layout.length >= nodes.length) {
                var groupClass = 'mer-mgroup is-active'
                    + (meridianUnlocked(meridian) ? '' : ' is-locked');
                parts.push('<g class="' + groupClass + '">');
                for (var n = 1; n < nodes.length; n++) {
                    var a = layout[n - 1];
                    var b = layout[n];
                    var segLit = _lit[nodes[n - 1].id] && _lit[nodes[n].id];
                    parts.push('<line class="mer-seg' + (segLit ? ' is-lit' : '')
                        + '" x1="' + a[0] + '" y1="' + a[1]
                        + '" x2="' + b[0] + '" y2="' + b[1]
                        + '" style="stroke-width:' + q(2.4 * k) + '"/>');
                }
                var labels = labelLayout(layout, nodes.length, k);
                for (n = 0; n < nodes.length; n++) {
                    var node = nodes[n];
                    var p = layout[n];
                    var isSel = _selectedNode === node.id;
                    var st = nodeState(meridian, n);
                    var dotClass = 'mer-dot is-' + st + (isSel ? ' is-selected' : '');
                    var tip = (meridian.name || meridian.id) + '·' + (node.name || node.id)
                        + '（' + bonusLabelOf(bonusTypeOf(node)) + ' +' + formatNumber(bonusAmountOf(node))
                        + '，' + nodeStateText(meridian, n, st) + '，'
                        + formatNumber(Number(node.cost) || 0) + ' K）';
                    if (st === 'next') {
                        parts.push('<circle class="mer-halo" cx="' + p[0] + '" cy="' + p[1]
                            + '" r="' + q((DOT_R + 3.5) * k) + '" style="stroke-width:' + q(1.6 * k) + '"/>');
                    }
                    parts.push('<circle class="' + dotClass + '" cx="' + p[0] + '" cy="' + p[1]
                        + '" r="' + q(DOT_R * k) + '" style="stroke-width:' + q((isSel ? 2.5 : 1.5) * k)
                        + '" data-node="' + escAttr(node.id) + '"><title>' + escAttr(tip) + '</title></circle>');
                    var lab = labels[n];
                    var dir = lab.right ? 1 : -1;
                    var x0 = p[0] + dir * (DOT_R + 1.5) * k;
                    var bend = x0 + dir * 6 * k;
                    // 按序未到/情报不足的穴暂时无可操作，引线压暗让下一穴跳出来；
                    // 标签只按贯通与否分白/绿（作者要求），不再跟着压暗。
                    var dim = st === 'sealed' || st === 'info' ? ' is-dim' : '';
                    parts.push('<polyline class="mer-leader' + dim + '" style="stroke-width:' + q(1.1 * k)
                        + '" points="' + q(x0) + ',' + q(p[1]) + ' ' + q(bend) + ',' + q(p[1])
                        + ' ' + q(lab.x - dir * 2 * k) + ',' + q(lab.ly) + '"/>');
                    parts.push('<text class="mer-dot-label' + (st === 'lit' ? ' is-lit' : '')
                        + '" style="font-size:' + q(LABEL_FONT * k) + 'px'
                        + '" x="' + q(lab.x) + '" y="' + q(lab.ly + LABEL_FONT * 0.32 * k) + '"'
                        + (lab.right ? '' : ' text-anchor="end"') + '>'
                        + escAttr(node.name || node.id) + '</text>');
                }
                parts.push('</g>');
            }
        }
        parts.push('</svg>');
        return parts.join('');
    }

    // 穴位标签排布：字号加大后单列容易挤到底，所以先按穴位横坐标定自然侧（贴中线的穴按序号交错），
    // 再沿 y 序逐穴落位——本侧放不下就插到对侧空位，两侧都紧才把本侧往下推。
    // 两列列位取所有穴位的最外侧再外推，标签一律在身体两侧，引线不会跨过人体。
    function labelLayout(layout, count, k) {
        var items = [];
        var minX = 1e9, maxX = -1e9, n;
        for (n = 0; n < count; n++) {
            var p = layout[n];
            items.push({
                y: p[1],
                right: Math.abs(p[0] - 210) < 6 ? (n % 2 === 1) : (p[0] > 210),
                x: 0,
                ly: p[1]
            });
            minX = Math.min(minX, p[0]);
            maxX = Math.max(maxX, p[0]);
        }
        placeLabelRows(items, LABEL_GAP * k);
        for (n = 0; n < count; n++) {
            items[n].x = items[n].right ? maxX + LABEL_COL * k : minX - LABEL_COL * k;
        }
        return items;
    }

    // 沿 y 序给每个标签找一行空位：自然侧空就用自然侧，否则插到对侧，两边都紧才顺延到本侧下一行。
    // 落位后整列若越出画布底界，按越出量回拉（不超过首行离顶的余量），保持行距不变。
    function placeLabelRows(items, gap) {
        var order = [];
        for (var i = 0; i < items.length; i++) order.push(i);
        order.sort(function (a, b) { return items[a].y - items[b].y; });
        var last = { right: -1e9, left: -1e9 };
        for (var o = 0; o < order.length; o++) {
            var it = items[order[o]];
            var want = it.right ? 'right' : 'left';
            var other = want === 'right' ? 'left' : 'right';
            var side = it.y >= last[want] + gap ? want
                : (it.y >= last[other] + gap ? other : want);
            it.right = side === 'right';
            last[side] = Math.max(it.y, last[side] + gap);
            it.ly = last[side];
        }
        pullColumnIntoView(items, true, last.right);
        pullColumnIntoView(items, false, last.left);
    }

    function pullColumnIntoView(items, isRight, bottom) {
        var overflow = bottom - 774;
        if (overflow <= 0) return;
        var top = 1e9;
        for (var i = 0; i < items.length; i++) {
            if (items[i].right === isRight) top = Math.min(top, items[i].ly);
        }
        if (top === 1e9) return;
        var shift = Math.min(overflow, top - 6);
        if (shift <= 0) return;
        for (i = 0; i < items.length; i++) {
            if (items[i].right === isRight) items[i].ly -= shift;
        }
    }

    function escAttr(text) {
        return String(text == null ? '' : text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function formatNumber(value) {
        var n = Math.round(Number(value) || 0);
        var text = String(Math.abs(n));
        var out = '';
        while (text.length > 3) {
            out = ',' + text.slice(-3) + out;
            text = text.slice(0, -3);
        }
        return (n < 0 ? '-' : '') + text + out;
    }

    function showStatus(text) {
        _refs.status.textContent = text;
        _refs.status.hidden = !text;
    }

    function showError(text) {
        _refs.error.textContent = text;
        _refs.error.hidden = !text;
    }

    // ========== 键盘 ==========
    // Escape / 遮罩点击由宿主经 Panels onRequestClose 统一下发（panels.js 生命周期合同），
    // 面板内不重复监听 keydown，避免双重关闭。

    function describeBoxForTest(box) {
        var kids = (box || {}).children || [];
        var parts = [];
        for (var i = 0; i < kids.length; i++) {
            parts.push(kids[i].className + '=' + kids[i].textContent
                + (kids[i].disabled === undefined ? '' : ' disabled=' + kids[i].disabled));
        }
        return { className: (box || {}).className, parts: parts };
    }

    return {
        applyStateForTest: function(resp) { applyState(resp); },
        getStateForTest: function() {
            return { meridians: _meridians, lit: _lit, kpoint: _kpoint, selectedIndex: _selectedIndex,
                selectedNode: _selectedNode, caps: _caps, used: _used, applied: _applied };
        },
        selectNodeForTest: function(nodeId) { selectNode(nodeId); },
        // 动作条/贯注区文本：桩测核对状态文案与按钮可用性（DOM 桩只保留 children）
        nodeBarForTest: function() { return describeBoxForTest(_refs.nodeBar); },
        actionForTest: function() { return describeBoxForTest(_refs.action); },
        requireListForTest: function() { return describeBoxForTest(_refs.requireList); },
        mapSvgForTest: function() { return _refs && _refs.canvas ? _refs.canvas.innerHTML : ''; },
        // 缩放态出图：离线核对点位/文字是否真的不随缩放变化（只走 zoomAt 这条真实入口）
        mapSvgAtZoomForTest: function(z) { zoomAt(z, 0, 0); return _refs.canvas.innerHTML; },
        layoutIdsForTest: function() {
            var ids = [];
            for (var key in NODE_LAYOUT) {
                if (Object.prototype.hasOwnProperty.call(NODE_LAYOUT, key)) ids.push(key);
            }
            return ids;
        }
    };
})();
