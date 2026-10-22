"""Bounded source-only canonical adoption for the two explicit sky manifests."""
from pathlib import Path
import importlib.util
import json

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('canonical_sky',HERE/'assemble-canonical.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)


def resolve(args):
    if args.door or args.map not in ('A02','A06') or args.layer!='background':raise ValueError('only A02/A06 sky adoption is supported')
    name='CF6_'+args.map+'_sky';candidate_name=name+'_VectorCandidate01'
    manifest=HERE/'layers'/candidate_name/'texture-manifest.json';m=json.loads(manifest.read_text(encoding='utf-8'))
    if m['schema']!='cf6-native-sky-input.v1' or m['map']!=args.map or m['name']!=candidate_name:raise ValueError('unexpected sky manifest')
    if api.sha(api.ROOT/m['source'])!=m['sourceSha256']:raise ValueError('sky authoring source changed')
    for row in m['inputs']:
        if api.sha(api.ROOT/row['path'])!=row['sha256']:raise ValueError('sky intrinsic source changed')
    candidate=api.safe(api.RESOURCE_ROOT/candidate_name,api.RESOURCE_ROOT);target=api.safe(api.RESOURCE_ROOT/name,api.RESOURCE_ROOT)
    api.audit(candidate/(candidate_name+'.xfl'),m['inputs'])
    return candidate_name,name,candidate,target,m['inputs'],manifest


if __name__=='__main__':api.resolve=resolve;api.main()
