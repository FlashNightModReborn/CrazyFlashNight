"""Read-only comparison of original cue sites, imported declarations and SFX decoding."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,re,struct,subprocess,zipfile
import numpy as np
from source import Source,scan

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OWNER_ROOTS={'Antigravity专用素材':[477,1694],'Codex蛮蛮素材':[692],'CodexWings素材':[873],
 'Codex特种兵素材':[559,580],'Codex光头保安素材':[888],'Codex大刀机器人素材':[925],
 'Codex大头机器人素材':[952],'Codex老头素材':[975,1011]}


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def decode(row):
    p=ROOT/row['path']
    if sha(p)!=row['sha256']:raise ValueError('Changed SFX '+row['name'])
    raw=subprocess.check_output(['ffmpeg','-hide_banner','-loglevel','error','-i',str(p),
        '-f','f32le','-ar','44100','-ac','2','pipe:1'])
    samples=np.frombuffer(raw,dtype='<f4')
    if not len(samples) or len(samples)%2 or not np.isfinite(samples).all() or not np.max(np.abs(samples))>0:
        raise ValueError('Empty, invalid or silent SFX '+row['name'])
    return {'name':row['name'],'sha256':row['sha256'],'decodedFrames':len(samples)//2,
        'durationSeconds':len(samples)/88200,'peak':float(np.max(np.abs(samples))),
        'rms':float(np.sqrt(np.mean(samples.astype(np.float64)**2))),'decodeToEnd':True}


def sprite_bodies(source):
    d=source.data;b=scan.Bits(d);n=b.u(5)
    for _ in range(4):b.s(n)
    b.align();bodies={}
    def walk(start,end):
        p=start
        while p<end-1:
            header=struct.unpack_from('<H',d,p)[0];p+=2;code,size=header>>6,header&63
            if size==63:size=struct.unpack_from('<I',d,p)[0];p+=4
            if code==39:
                cid=struct.unpack_from('<H',d,p)[0];bodies[cid]=d[p+4:p+size];walk(p+4,p+size)
            p+=size
            if code==0:break
    walk(b.byte+4,len(d));return bodies


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source-swf',type=Path,required=True)
    parser.add_argument('--baseline-zip',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();source=Source(args.source_swf)
    config=json.loads((HERE/'cues.json').read_text('utf8'));assets=json.loads((HERE/'assets.json').read_text('utf8'))
    if source.sha256!=config['sourceSwfSha256']:raise ValueError('Wrong original source')
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    groups=[]
    with zipfile.ZipFile(args.baseline_zip) as baseline:
        for owner,roots in OWNER_ROOTS.items():
            declared={(r['source'][0],r['source'][1],cid) for r in config['owners'][owner]['cues'] if r['source'] for cid in r['soundIds']}
            declared.update((r['source'][0],r['source'][1],r['soundId']) for r in config['runtimeCues'] if r['owner']==owner and r.get('source'))
            sites=[]
            for root in roots:
                closure=source.closure(root)
                for e in source.events:
                    if e['spriteId'] not in closure:continue
                    key=(e['spriteId'],e['frame'],e['soundId'])
                    retained=owner=='CodexWings素材' and e['spriteId']==868 and e['frame'] in (20,23,26,29,38)
                    if key not in declared and not retained:raise ValueError('Unaccounted original cue '+str(key))
                    sites.append({'originalRoot':root,**e,'before':'CF7 slash sound retained' if retained else 'original action cue absent',
                        'after':'existing native SFX adaptation' if retained else 'root native SFX call restored'})
            rel='flashswf/arts/new/'+owner+'.swf';copy=output/('before-'+owner+'.swf');copy.write_bytes(baseline.read(rel))
            before=Source(copy);after=Source(ROOT/rel)
            if after.sounds or after.events:raise ValueError('Embedded sound found in current consumer '+owner)
            groups.append({'owner':owner,'originalRoots':roots,'sites':sites,
                'originalTimelineSites':len(sites),'missingOriginalTimelineSites':sum(x['before']=='original action cue absent' for x in sites),
                'currentTimelineCallSites':len(config['owners'][owner]['cues']),
                'beforeSwfSha256':before.sha256,'afterSwfSha256':after.sha256,
                'beforeEmbeddedDefinitions':len(before.sounds),'beforeEmbeddedStarts':len(before.events),
                'afterEmbeddedDefinitions':len(after.sounds),'afterEmbeddedStarts':len(after.events)})
    known={p.name:p for p in (ROOT/'sounds/export').glob('*/*') if p.is_file()}
    legacy=[]
    legacy_config=json.loads((HERE/'legacy-cues.json').read_text('utf8'))
    legacy_assets=json.loads((HERE/'legacy-assets.json').read_text('utf8'))
    legacy_wav=legacy_assets['files'][0]
    legacy_decoded=decode({'path':legacy_wav['target'],'sha256':legacy_wav['sha256'],'name':Path(legacy_wav['target']).name})
    for rel,links in [('flashswf/arts/new/素材库-诺亚新敌人.swf',['敌人-诺亚克隆兽','敌人-闪6特工']),
        ('flashswf/arts/new/Codex专用素材.swf',['敌人-延寿克隆兽','敌人-完全体克隆兽'])]:
        current=Source(ROOT/rel);bodies=sprite_bodies(current)
        for link in links:
            cid=next(k for k,v in current.exports.items() if v==link);closure=current.closure(cid)
            embedded=[e for e in current.events if e['spriteId'] in closure]
            if embedded:raise ValueError('Embedded sound in a CF6 legacy consumer '+link)
            declared=[]
            for sid in sorted(closure):
                raw=bodies.get(sid,b'')
                names=set()
                for value in raw.split(b'\0'):
                    try:text=value.decode('utf8')
                    except UnicodeDecodeError:continue
                    if re.fullmatch(r'[^\\/:*?"<>|\x00-\x1f\x7f]{1,128}\.(?:wav|mp3|ogg|flac)',text,re.I):names.add(text)
                names=sorted(names)
                if names:declared.append({'spriteId':sid,'sfxStrings':names,
                    'missingFiles':[name for name in names if name not in known],
                    'containsRootPlaySoundName':'播放音效'.encode('utf8')+b'\0' in raw})
            agent=link==legacy_config['linkage']
            original_root=873 if agent else 353
            original_sites=[e for e in source.events if e['spriteId'] in source.closure(original_root)]
            legacy.append({'linkage':link,'swf':rel,'swfSha256':current.sha256,'declaredInSpriteClosure':declared,
                'embeddedStartSoundsInConsumerClosure':len(embedded),
                'wholeLibraryEmbeddedSoundDefinitions':len(current.sounds),'wholeLibraryEmbeddedStartSounds':len(current.events),
                'missingFiles':sorted({name for row in declared for name in row['missingFiles']}),
                'originalRoot':original_root,'originalTimelineSites':original_sites,
                'originalEffectSitesMissingBefore':2 if agent else None,
                'restoredOriginalEffectSites':legacy_config['cues'] if agent else [],
                'comparisonBoundary':'Five original strike sites already use CF7 effects; first weapon and landing effects are restored separately from the retained vocal library.' if agent else 'CF7 rewrote the movement, combo and death sequence; nine original timeline sites cannot be treated as nine comparable missing calls. Existing footsteps, claw, jump, landing and roars are retained; missing death WAV restored for both present death calls.',
                'swfUnchangedByThisTask':rel.endswith('/Codex专用素材.swf'),
                'scope':'exact null-delimited SFX literals in current SWF closure; original-site mapping and actual invocation have separate receipts; not runtime endpoint listening acceptance'})
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:decoded=list(pool.map(decode,assets['files']))
    summary={'schema':'cf6.audio-audit.v1','originalSwfSha256':source.sha256,'baselineZipSha256':sha(args.baseline_zip),
        'newLibraryCount':len(groups),'newUnitOrFormCount':12,'legacyAndDerivedUnits':legacy,
        'originalTimelineSitesInNewLibraries':sum(g['originalTimelineSites'] for g in groups),
        'originalTimelineSitesMissingBefore':sum(g['missingOriginalTimelineSites'] for g in groups),
        'originalTimelineSitesMissingAfter':0,'afterCoverageKind':'generated call mapping plus current SWF no-embedded-audio scan; actual frame invocation has separate native suite receipts',
        'timelineSiteCountingBoundary':'StartSound sites in eleven original roots; shared actor variants counted once; script voices, weapon configuration and extended transformation are separate',
        'nativeTimelineCalls':sum(g['currentTimelineCallSites'] for g in groups),
        'legacyAdditionalNativeCalls':len(legacy_config['cues']),
        'restoredLegacyWav':legacy_decoded,
        'voiceRouteReplacements':2,'newSfxFiles':len(assets['files']),'newSfxBytes':assets['bytes'],
        'embeddedAudioInNewSwfs':0,'groups':groups,'runtimeCues':config['runtimeCues'],
        'additionalPhaseTimelineCues':[e for e in source.events if e['spriteId']==2008],
        'decodedAssets':decoded,'decodedWith':'ffmpeg offline; not native endpoint or human listening acceptance',
        'newNativeEndpointListeningVerified':False}
    (output/'audit.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n','utf8')
    print(json.dumps({k:summary[k] for k in ['newLibraryCount','newUnitOrFormCount','originalTimelineSitesInNewLibraries','originalTimelineSitesMissingBefore','originalTimelineSitesMissingAfter','nativeTimelineCalls','newSfxFiles','newSfxBytes','embeddedAudioInNewSwfs']},ensure_ascii=False))


if __name__=='__main__':main()
