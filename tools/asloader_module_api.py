"""Derive compile-only AS2 signatures; never generate substitute runtime implementations."""
import re

def mask(source):
    return re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*[\s\S]*?\*/|//[^\r\n]*',
        lambda m: re.sub(r'[^\r\n]',' ',m.group()),source)

def end_brace(text,start):
    depth=0
    for at in range(start,len(text)):
        if text[at]=='{': depth+=1
        elif text[at]=='}':
            depth-=1
            if depth==0: return at+1
    raise ValueError('Unbalanced member body')

def declaration(source,fqn,provider="asLoaderShared.swf"):
    masked=mask(source)
    header=re.search(r'\b(class|interface)\s+'+re.escape(fqn)+r'\b',masked)
    if not header: raise ValueError('Class identity unavailable '+fqn)
    start=masked.index('{',header.end())
    finish=end_brace(masked,start)
    cursor=start+1
    replacements=[]
    while cursor<finish-1:
        match=re.search(r'\b(function|var)\b',masked[cursor:finish-1])
        if not match: break
        at=cursor+match.start()
        # Every previous member is consumed whole, so this is a class member.
        if match.group()=='function':
            brace=masked.find('{',at,finish-1)
            semi=masked.find(';',at,finish-1)
            if semi>=0 and (brace<0 or semi<brace):
                cursor=semi+1;continue
            if brace<0: raise ValueError('Member has no terminator '+fqn)
            end=end_brace(masked,brace)
            replacements.append((brace,end,';'))
            cursor=end
        else:
            at+=3
            depths={'(':0,'[':0,'{':0}
            pairs={')':'(',']':'[','}':'{'}
            initializer=None
            while at<finish-1:
                char=masked[at]
                top=not any(depths.values())
                if top and char=='=' and initializer is None: initializer=at
                if top and char in ',;':
                    if initializer is not None:
                        replacements.append((initializer,at,''));initializer=None
                    if char==';': break
                if char in depths: depths[char]+=1
                elif char in pairs: depths[pairs[char]]-=1
                at+=1
            cursor=at+1
    for begin,end,value in sorted(replacements,reverse=True): source=source[:begin]+value+source[end:]
    source=re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*[\s\S]*?\*/|//[^\r\n]*',
        lambda match: match.group() if match.group()[0] in "\"'" else re.sub(r'[^\r\n]',' ',match.group()),source)
    if header.group(1)=='class':
        source=re.sub(r'\bclass\s+'+re.escape(fqn)+r'\b','intrinsic class '+fqn,source,count=1)
    source=re.sub(r'\n[ \t]*\n(?:[ \t]*\n)+','\n\n',source)
    return '// Generated compile-only declarations; runtime bodies: '+provider+'.\n'+source.strip()+'\n'
