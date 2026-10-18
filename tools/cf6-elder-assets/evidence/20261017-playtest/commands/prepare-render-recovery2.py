from pathlib import Path
import json
p=Path(__file__).resolve().parent
s=(p/'recover-render-stop1.ps1').read_text('utf8')
s=s.replace('render-stop1','render-stop2').replace('render-pass1/elder','render-pass2/headbot').replace("name='elder'","name='headbot'")
control=json.loads((p/'render-stop2/control-folder.json').read_text('utf-8-sig'))['folder']
old="Join-Path $repo 'tmp/flash-testplayer-control/26208947b22e4c1aa411ea6e0ceee0f8'"
assert old in s
s=s.replace(old,"'"+control.replace("'","''")+"'")
s=s.replace("-notmatch 'closed=true'","-notmatch 'closed=false'",1)
(p/'recover-render-stop2.ps1').write_text(s,'utf-8-sig')
