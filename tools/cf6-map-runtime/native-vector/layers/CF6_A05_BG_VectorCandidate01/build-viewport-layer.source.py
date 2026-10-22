"""A05/A06-only viewport fix; the K3 r1b generic converter remains frozen."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import sys
import uuid
import zipfile

from viewport_adapter import candidate_class

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def preserve_candidate(name):
    target=ROOT/'flashswf/backgrounds/cf6'/name
    swf=target.parent/(name+'.swf');derived=HERE/'layers'/name
    token=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
    folder=HERE/'archive/viewport-pre-adapter'/name/token;folder.mkdir(parents=True)
    rows=[]
    for label,directory in [('candidate',target),('derived',derived)]:
        if directory.is_dir():
            for path in sorted(directory.rglob('*')):
                if path.is_file():rows.append((path,label+'/'+path.relative_to(directory).as_posix()))
    if swf.is_file():rows.append((swf,'candidate-swf/'+swf.name))
    inventory=[{'path':label,'sha256':sha(path),'bytes':path.stat().st_size} for path,label in rows]
    archive=folder/'previous.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
        for path,label in rows:z.write(path,label)
    with zipfile.ZipFile(archive) as z:
        for row in inventory:
            if hashlib.sha256(z.read(row['path'])).hexdigest()!=row['sha256']:raise ValueError('archive verification failed')
    receipt={'schema':'cf6-viewport-pre-adapter-archive.v1','archive':archive.relative_to(ROOT).as_posix(),'archiveSha256':sha(archive),'files':inventory,'scope':'previous candidate source, derived report and SWF preserved before source-only rebuild'}
    (folder/'previous.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return {'receipt':(folder/'previous.json').relative_to(ROOT).as_posix(),'archiveSha256':receipt['archiveSha256']}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--map',required=True,choices=['A05','A06']);parser.add_argument('--assemble',action='store_true');args=parser.parse_args()
    signal=HERE/'batch/converter-ready.json';ready=json.loads(signal.read_text(encoding='utf-8'))
    for row in ready['files']:
        if sha(ROOT/row['path'])!=row['sha256']:raise ValueError('frozen converter input changed: '+row['path'])
    name='CF6_'+args.map+'_BG_VectorCandidate01'
    previous=preserve_candidate(name)
    spec=importlib.util.spec_from_file_location('viewport_generic',HERE/'build-layer.py');generic=importlib.util.module_from_spec(spec);spec.loader.exec_module(generic)
    ViewportCandidate=candidate_class(generic.api);instances=[]
    class TrackedCandidate(ViewportCandidate):
        def __init__(self,*a,**kw):
            super().__init__(*a,**kw);instances.append(self)
    generic.api.Candidate=TrackedCandidate
    sys.argv=[str(HERE/'build-layer.py'),'--map',args.map]+(['--assemble'] if args.assemble else [])
    generic.main()
    if len(instances)!=1:raise ValueError('expected exactly one source converter')
    viewports=instances[0].viewport_reports;expected=14 if args.map=='A05' else 42
    if len(viewports)!=expected:raise ValueError('nested viewport source census changed; inspect before adopting output')
    out=HERE/'layers'/name;p=out/'report.json';report=json.loads(p.read_text(encoding='utf-8'))
    scripts=[Path(__file__),HERE/'viewport_adapter.py'];dependencies=[{'path':s.relative_to(ROOT).as_posix(),'sha256':sha(s),'bytes':s.stat().st_size} for s in scripts]
    report.update(nestedViewports=viewports,specializedConverterInputs=dependencies,baselineConverterBundleSha256=ready['converterBundleSha256'],baselineSignalSha256=sha(signal),previousCandidateArchive=previous,
        visualEvidenceScope='Standalone CF6_A05_PartsDiagnostic02 actual FP11 comparison confirmed multiply+viewport parts; rebuilt A05/A06 full-map candidates still require fresh compile and consumer verification.')
    p.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for source in scripts:(out/(source.stem+'.source.py')).write_bytes(source.read_bytes())
    print(json.dumps({'map':args.map,'nestedViewports':len(viewports),'adapterInputs':dependencies,'previous':previous,'state':report['state']},ensure_ascii=False))


if __name__=='__main__':main()
