"""Hash-bound original MP3/PCM extraction and reuse; no new audio synthesis or service."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import io
import json
import wave

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
ORIGINAL=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/crazyflasher6-cn.swf'
PIN='b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def build(check=False):
    path=ROOT/'tools/cf6-audio/source.py';spec=importlib.util.spec_from_file_location('vehicle_sound_source',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);source=module.Source(ORIGINAL)
    if source.sha256!=PIN:raise ValueError('original sound source identity mismatch')
    outputs={};new=[]
    for cid in [626,1160,1161,1162,1163,1169]:
        meta=source.sound_metadata(cid)
        if meta['codec']==2:raw=source.sound_payload(cid);suffix='mp3';derivation='unchanged original MP3 payload'
        elif meta['codec']==3:
            pcm=source.sounds[cid]['body'][7:]
            stride=meta['channels']*meta['bits']//8
            frames=len(pcm)//stride
            # Three original headers overstate their PCM payload by 2-3 frames.
            # Preserve every actual sample; do not synthesize padding or relabel it lossless.
            if len(pcm)%stride or frames!={1160:7668,1161:7736,1162:8216,1163:9464}[cid]:raise ValueError('PCM source payload identity mismatch')
            meta['actualPcmFrames']=frames;meta['declaredMinusActualFrames']=meta['sampleCount']-frames
            stream=io.BytesIO()
            with wave.open(stream,'wb') as wav:
                wav.setnchannels(meta['channels']);wav.setsampwidth(meta['bits']//8);wav.setframerate(meta['rate']);wav.writeframes(pcm)
            raw=stream.getvalue();suffix='wav';derivation='unchanged original little-endian PCM samples with RIFF header'
            meta['pcmSha256']=sha(pcm)
        else:raise ValueError('unsupported original sound codec')
        target=ROOT/'sounds/export/人物'/f'CF6Vehicle_{cid:04d}.{suffix}';outputs[target]=raw
        new.append({'path':target.relative_to(ROOT).as_posix(),'name':target.name,'soundId':cid,
            'sha256':sha(raw),'bytes':len(raw),'source':meta,'derivation':derivation})
    reused=[]
    for cid in [915,1009,1121,1135,1144,1123,1137,1146,1151,1154,1157]:
        target=ROOT/'sounds/export/人物'/f'CF6_{cid:04d}.mp3';raw=target.read_bytes()
        if raw!=source.sound_payload(cid):raise ValueError('existing CF6 sound differs from original '+target.name)
        reused.append({'path':target.relative_to(ROOT).as_posix(),'name':target.name,'soundId':cid,'sha256':sha(raw),'bytes':len(raw)})
    names={r['soundId']:r['name'] for r in new+reused}
    cues={'gun':[names[1169]],'metal':[names[i] for i in [1160,1161,1162,1163]],
        'raiderDown':[names[i] for i in [1121,1135,1144]],'raiderDeath':[names[i] for i in [1123,1137,1146,1151,1154,1157]],
        'obstacle':[names[626]],'vehicleDeath':[names[915]],'explosion':[names[1009]]}
    events=[{'source':'global 汽车_子弹区域shoot / source1803 frame8 two muzzle intervals','cue':'gun','delivery':'two barrels, immediately and every 150ms while firing'},
        {'source':'sprite612/627 contact and sprite115 frame1','cue':'metal','delivery':'once per contact or source spark instance'},
        {'source':'sprite612 frame70 child599 load','cue':'raiderDown','delivery':'one terminal road knockdown'},
        {'source':'sprite612 frame77 child611 load','cue':'raiderDeath','delivery':'one terminal shot death'},
        {'source':'StartSound sprite627 frame3 sound626','cue':'obstacle','delivery':'one obstacle break'},
        {'source':'StartSound sprite1803 frame16 and sprite1813 frame121 sound915','cue':'vehicleDeath','delivery':'once on actual player/boss death'},
        {'source':'StartSound sprite1813 frames131,142 and script sprite391 frame2 sound1009','cue':'explosion','delivery':'source boss departure frames and each grenade explosion'}]
    inputs=[Path(__file__),path,ROOT/'tools/swf-audit/swfscan.py',ORIGINAL,ROOT/'tools/cf6-audio/assets.json']
    manifest={'schema':'cf6-vehicle-audio.v1','sourceSha256':PIN,'inputs':{p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in inputs},
        'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(raw),'bytes':len(raw)} for p,raw in outputs.items()},
        'new':new,'reused':reused,'cues':cues,'events':events,
        'delivery':'existing _root.播放音效 -> AudioBridge; no embedded SWF audio',
        'catalog':'AudioCoordinator.ScanDefaultCatalog enumerates sounds/export packs at startup; full filename is linkage ID; restart required',
        'validationBoundary':'file identity and consumer calls are distinct; no speaker/listening qualification claimed'}
    outputs[HERE/'audio-manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for target,raw in outputs.items():
        if check:
            if not target.is_file() or target.read_bytes()!=raw:raise ValueError('stale vehicle audio '+str(target))
        elif target.is_file() and target.read_bytes()!=raw:
            if target.name!='audio-manifest.json':raise ValueError('preserve independently changed sound '+str(target))
            target.write_bytes(raw)
        elif not target.is_file():target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    print(json.dumps({'state':'checked' if check else 'prepared','newSounds':len(new),'reusedSounds':len(reused),'newBytes':sum(r['bytes'] for r in new)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');build(parser.parse_args().check)
