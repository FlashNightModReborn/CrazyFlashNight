from pathlib import Path
import hashlib,json,re
R=Path.cwd();D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
source=json.loads((D/'source-scope-before.json').read_text('utf8'))
token_re=re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[\w\u0080-\uffff]+|[^\s]',re.UNICODE)
rows=[]
for entry in source['files']:
    raw=(R/entry['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==entry['sha256']
    text=raw.decode('utf-8-sig')
    tokens=[(m.group(),text.count('\n',0,m.start())+1) for m in token_re.finditer(text)
            if not m.group().startswith(('//','/*','"',"'"))]
    stack=[];depth=0;pending=False;outer=[]
    for value,line in tokens:
        if value=='function':pending=True
        elif value=='{':stack.append(pending);depth+=int(pending);pending=False
        elif value=='}':depth-=int(stack.pop())
        elif depth==0 and value in ['return','arguments','with','eval']:outer.append({'token':value,'line':line})
    assert not stack and not pending
    rows.append({'path':entry['path'],'outerControlOrDynamicScopeTokens':outer})
result={'qualified':not any(x['outerControlOrDynamicScopeTokens'] for x in rows),'files':rows,
    'boundary':'Read-only lexical audit: no outer early return, arguments object, with scope or eval straddles the chunk split. Same receiver, literal body concatenation and no outer locals are recorded separately.'}
with (D/'split-control-flow.json').open('x',encoding='utf8') as f:json.dump(result,f,ensure_ascii=False,indent=2)
print(json.dumps(result,ensure_ascii=False));assert result['qualified']
