# 褰撳墠钀藉湴鐘舵€?
`tools/cf7-balance-tool` 褰撳墠宸茬粡鍙互浣滀负鏁板€煎钩琛″伐鍏风殑绗竴鐗堟妧鏈簳搴т娇鐢ㄣ€?
## 宸查獙璇侊紙2026-03-06锛?
- `npm install`
- `npm run typecheck`
- `npm test`
- `npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json`
- `npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json`
- `npm run batch-set -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output`

## 褰撳墠鑳藉姏闈?
- `packages/core`锛氬瓧娈靛垎绫汇€佸叡浜绾︺€佸瓧娈垫敞鍐岃〃
- `packages/xml-io`锛氶」鐩壂鎻忋€佸瓧娈垫姤鍛娿€乆ML round-trip 鏂囨。瀵硅薄銆侀」鐩骇 round-trip 鏍￠獙銆佹壒閲忔敼鍊艰緭鍑?- `packages/cli`锛歚project scan` / `project fields` / `project roundtrip-check` / `project batch-set` / `xml get` / `xml set`
- `packages/web`锛欵lectron + React 涓枃浼樺厛澹筹紝鐩存帴娑堣垂瀛楁鎵弿鎶ュ憡

## 褰撳墠鍩虹嚎

- 宸叉壂鎻?XML锛?9
- 瀛楁鍚嶏細528
- 瀛楁鍑虹幇娆℃暟锛?6854
- 鏈垎绫诲瓧娈碉細394
- 椤圭洰绾?round-trip 鏍￠獙锛?9 / 89 閫氳繃

瀛楁鎵弿鍣ㄥ綋鍓嶄粛鏄瘝娉曟壂鎻忥紝閫傚悎瀛楁鐩樼偣鍜屾湭鐭ュ瓧娈垫敹鏁涳紱鐪熸鐨?XML 璇诲啓鑳藉姏宸茬粡鐢?`XmlDocument` 鎻愪緵锛屽苟宸叉帴鍏?CLI銆?
## 甯哥敤鍛戒护

```bash
npm install
npm run typecheck
npm test
npm run project-scan -- --project ./project.json
npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json
npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json
npm run batch-set -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output
.\node_modules\.bin\tsx.cmd packages/cli/src/index.ts xml get --file ../../data/items/姝﹀櫒_鎵嬫灙_鍘嬪埗鏈烘灙.xml --path root.item[0].data.power
.\node_modules\.bin\tsx.cmd packages/cli/src/index.ts xml set --file ../../data/items/姝﹀櫒_鎵嬫灙_鍘嬪埗鏈烘灙.xml --path root.item[1].data.power --value 55 --output ./reports/weapon-power-sample.xml
npm run dev:web
npm run dev:electron
```

## 璺緞绾﹀畾

- `xmlPath` 鐨勯噸澶嶈妭鐐圭储寮曟槸 0-based锛屼緥濡傜涓€鎶婃鍣ㄦ槸 `root.item[0]`锛岀浜屾妸鏄?`root.item[1]`
- `project batch-set` 鐨勭浉瀵?`filePath` 浼氬厛鎸夎緭鍏?JSON 鎵€鍦ㄧ洰褰曡В鏋愶紝鎵句笉鍒版椂鍐嶅洖閫€鍒?`project.json` 鎵€鍦ㄧ洰褰曡В鏋?- `project batch-set --output-dir` 浼氭寜椤圭洰鍏叡鏍归暅鍍忚緭鍑猴紝涓嶄細鏀瑰姩鍘熷 `data/` 鏂囦欢

## 楠岃瘉浜х墿

- 瀛楁鎶ュ憡锛歚reports/field-usage-report.json`
- round-trip 鎶ュ憡锛歚reports/roundtrip-report.json`
- 鎵归噺鏀瑰€艰緭鍏ユ牱渚嬶細`reports/batch-updates.sample.json`
- 鎵归噺鏀瑰€兼姤鍛婏細`reports/batch-set-report.json`
- 鎵归噺鏀瑰€艰緭鍑烘牱渚嬶細`reports/batch-output/data/items/姝﹀櫒_鎵嬫灙_鍘嬪埗鏈烘灙.xml`
- 鍗曟枃浠舵敼鍊兼牱渚嬶細`reports/weapon-power-sample.xml`

## 褰撳墠缂哄彛

- 鍏紡妯″潡浠嶆槸鍗犱綅锛屽皻鏈繘鍏ユ鍣?鑽墏/缁忔祹鍏紡缈昏瘧
- 鏈垎绫诲瓧娈典粛鏈?394 涓紝涓昏闆嗕腑鍦?`list.xml`銆乣hairstyle.xml`銆乣missileConfigs.xml` 鍜岄儴鍒嗘秷鑰楀搧鍏冩暟鎹?- Electron 杩樻病鏈夋帴 diff銆佹壒閲忕紪杈戣〃鏍笺€佹牎楠屾彁绀洪潰鏉?- CLI 鐜板湪宸茬粡鑳藉仛椤圭洰绾ф牎楠屽拰鎵归噺瀵煎嚭锛屼絾杩樻病鏈夊彉鏇撮瑙堝拰鍐茬獊妫€鏌