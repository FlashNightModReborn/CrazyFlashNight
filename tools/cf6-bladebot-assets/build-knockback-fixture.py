"""Bind the small AS2 regression fixture to the exact production function body."""
from pathlib import Path
import hashlib,json,argparse,shutil
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/"scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"
text=source.read_text(encoding="utf-8-sig")
start=text.index("_root.敌人函数.被击移动 = function(")
end=text.index("_root.敌人函数.强制移动",start)
body=text[start:end].strip()
assert body.endswith("};")
folder=ROOT/"scripts/test-runners/cf6-knockback-scope";folder.mkdir(exist_ok=True)
target=folder/"TestLoader.as.template"
value='import org.flashNight.arki.unit.Action.Melee.*;\n_root.敌人函数={};\n'+body+'\n_root.cf6KnockbackScopeComplete=function():Void {trace("FocusedTestRunId cf6-knockback-scope Complete: __FOCUSED_RUN_ID__");};\ntrace("FocusedTestRunId cf6-knockback-scope Start: __FOCUSED_RUN_ID__");\norg.flashNight.arki.unit.Action.Melee.Cf6KnockbackScopeTest.runAllTests();\n'
args=argparse.ArgumentParser();args.add_argument("--check",action="store_true");options=args.parse_args()
fragment=folder/"EnemyKnockbackFixture.as"
if options.check:
    assert target.read_text(encoding="utf-8-sig")==value
    assert fragment.read_text(encoding="utf-8-sig")==body+"\n"
else:
    target.write_text(value,encoding="utf-8-sig",newline="\n")
    if not fragment.exists():shutil.copy2(source,fragment)
    fragment.write_text(body+"\n",encoding="utf-8-sig",newline="\n")
print(json.dumps({"source":source.relative_to(ROOT).as_posix(),"functionSha256":hashlib.sha256(body.encode()).hexdigest(),"templateSha256":hashlib.sha256(target.read_bytes()).hexdigest()},ensure_ascii=False))
