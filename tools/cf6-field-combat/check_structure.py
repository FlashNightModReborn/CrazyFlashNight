"""Lexical delimiter check only. This does not replace real CS6/AVM1 compilation."""
from pathlib import Path
import re

def check(path):
    text=path.read_text(encoding='utf-8-sig')
    # Preserve newlines while masking quoted strings and comments.
    token=re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/')
    masked=token.sub(lambda m: re.sub(r'[^\n]',' ',m.group()),text)
    stack=[];matches={')':'(',']':'[','}':'{'};line=1
    for ch in masked:
        if ch=='\n':line+=1
        elif ch in '([{':stack.append((ch,line))
        elif ch in ')]}':
            if not stack or stack[-1][0]!=matches[ch]:
                raise ValueError(f'{path}:{line}: mismatched {ch}; opening={stack[-1:]!r}')
            stack.pop()
    if stack:raise ValueError(f'{path}: unclosed delimiters {stack!r}')
    return {'file':str(path),'lines':line,'delimiterCheck':'pass','compilerProof':False}

if __name__=='__main__':
    import json
    print(json.dumps(check(Path(__file__).with_name('Cf6FieldCombatTest.as.txt'))))
