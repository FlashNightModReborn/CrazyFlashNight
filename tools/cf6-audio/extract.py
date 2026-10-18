"""Extract named native SFX from the hash-bound original; bake its six envelope uses offline."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import wave
import io
import numpy as np
from source import Source

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=ROOT/'sounds/export/人物'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_name(cid,envelope=None):
    if envelope:
        key=digest(json.dumps(envelope,sort_keys=True,separators=(',',':')).encode())[:10]
        return f'CF6_{cid:04d}_{key}.wav'
    return f'CF6_{cid:04d}.mp3'


def pcm_envelope(mp3,envelope):
    pcm=subprocess.check_output(['ffmpeg','-hide_banner','-loglevel','error','-i','pipe:0',
        '-f','f32le','-ar','44100','-ac','2','pipe:1'],input=mp3)
    samples=np.frombuffer(pcm,dtype='<f4').reshape(-1,2).copy()
    positions=np.arange(len(samples),dtype=np.float64)
    points=np.array([row['position44'] for row in envelope],dtype=np.float64)
    for i,key in enumerate(('left','right')):
        levels=np.array([row[key]/32768 for row in envelope])
        samples[:,i]*=np.interp(positions,points,levels)
    out=io.BytesIO()
    with wave.open(out,'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(44100)
        f.writeframes(np.clip(np.rint(samples*32768),-32768,32767).astype('<i2').tobytes())
    return out.getvalue()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source-swf',required=True,type=Path)
    parser.add_argument('--write',action='store_true')
    args=parser.parse_args()
    source=Source(args.source_swf)
    cues=json.loads((HERE/'cues.json').read_text('utf8'))
    if source.sha256!=cues['sourceSwfSha256']:
        raise ValueError('Original SWF identity does not match the audited source')
    required={}
    for group in cues['owners'].values():
        for cue in group['cues']+group.get('replacements',[]):
            for cid in cue['soundIds']:
                required[file_name(cid)]=(cid,None)
                if cue.get('envelope'):required[file_name(cid,cue['envelope'])]=(cid,cue['envelope'])
    for cue in cues['runtimeCues']:
        if 'soundId' in cue:required[file_name(cue['soundId'])]=(cue['soundId'],None)
    previous=json.loads((HERE/'assets.json').read_text('utf8')) if (HERE/'assets.json').exists() else {'files':[]}
    old={r['name']:r for r in previous['files']}
    rows=[]
    for name,(cid,envelope) in sorted(required.items()):
        raw=source.sound_payload(cid)
        payload=pcm_envelope(raw,envelope) if envelope else raw
        target=OUT/name
        if args.write:
            if target.exists() and digest(target.read_bytes())!=digest(payload):
                if name not in old or digest(target.read_bytes())!=old[name]['sha256']:
                    raise ValueError('Preserve independently modified sound: '+str(target))
            target.write_bytes(payload)
        if not target.exists() or target.read_bytes()!=payload:
            raise ValueError('Missing or stale extracted SFX: '+name)
        rows.append({'name':name,'path':target.relative_to(ROOT).as_posix(),'soundId':cid,
            'bytes':len(payload),'sha256':digest(payload),'source':source.sound_metadata(cid),
            'derivation':'decoded PCM with source envelope' if envelope else 'unmodified MP3 payload',
            'envelope':envelope})
    result={'schema':'cf6.audio-assets.v1','sourceSwfSha256':source.sha256,'sourceFps':source.fps,
        'cuesSha256':digest((HERE/'cues.json').read_bytes()),
        'ffmpegVersion':subprocess.check_output(['ffmpeg','-version'],text=True,encoding='utf8').splitlines()[0],
        'files':rows,'bytes':sum(r['bytes'] for r in rows),'embeddedSoundTracks':0}
    if args.write:(HERE/'assets.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
    elif previous!=result:raise ValueError('Audio manifest is stale')
    print(json.dumps({'ok':True,'files':len(rows),'bytes':result['bytes'],'embeddedSoundTracks':0}))


if __name__=='__main__':main()
