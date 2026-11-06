"""Regress stale artwork references when nested PNG animation becomes WebP."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('icon_webp_migration',ROOT/'tools/bake-icons-offline.py')
tool=importlib.util.module_from_spec(spec);sys.modules[spec.name]=tool;spec.loader.exec_module(tool)

old={'f1':'old.png','f2':'old_detail.png','frames':[{'uri':'old.png'}],
     'timelineFrames':[{'uri':'old.png','durationFrames':4}],
     'nestedAnimation':{'characterId':10,'legacy':True},'format':'png-sequence',
     'customMetadata':{'owner':'unchanged'}}
fresh={'f1':'new_static.webp','uri':'new_animation.webp','format':'webp-animated',
       'frameCount':32,'fps':30,'animated':True,
       'nestedAnimation':{'characterId':20,'sourceFrameCount':32}}
entry=deepcopy(old);snapshot=deepcopy(fresh)
tool.merge_webp_animation_entry(entry,fresh)
assert all(k not in entry for k in ['f2','frames','timelineFrames'])
assert entry['nestedAnimation']==fresh['nestedAnimation']
assert 'legacy' not in entry['nestedAnimation']
assert entry['customMetadata']==old['customMetadata']
assert fresh==snapshot
with_detail={**fresh,'f2':'explicit_new_detail.webp'}
tool.merge_webp_animation_entry(entry,with_detail)
assert entry['f2']=='explicit_new_detail.webp'
try:
    tool.merge_webp_animation_entry(entry,{'format':'png-sequence'})
    raise AssertionError('Invalid format was accepted')
except ValueError:
    pass
print('Animated WebP migration: stale sequence removed, fresh detail preserved, metadata retained')
