"""A08-specific small vent-wear approximation; frozen generic converter is unchanged."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import re
import sys

from procedural_filter import vent_wear

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('cf6_a08_generic',HERE/'build-layer.py')
generic=importlib.util.module_from_spec(spec);spec.loader.exec_module(generic)
Base=generic.api.Candidate
noise_reports=[]


class A08Candidate(Base):
    def walk_native(self,node,inherited=None,mask_mode=False):
        ref=node.get('filter','');match=re.fullmatch(r'url\(#([^)]*)\)',ref)
        if match:
            definition=self.byid.get(match.group(1))
            if definition is not None and any(generic.api.tag(child)=='feTurbulence' for child in definition):
                if mask_mode or generic.api.tag(node)!='path' or node.get('transform'):raise ValueError('A08 procedural fallback is bounded to the reviewed vent path')
                script,report=vent_wear(definition)
                points=[point for path in generic.api.base.primitive(node) for point in generic.api.base.flattened(path)]
                xs=[p[0] for p in points];ys=[p[1] for p in points]
                bounds=[min(xs),min(ys),max(xs),max(ys)]
                if bounds[2]-bounds[0]>512 or bounds[3]-bounds[1]>128:raise ValueError('vent patch exceeded the reviewed bounds')
                clone=copy.deepcopy(node);clone.attrib.pop('filter')
                content=self.instance(super().walk_native(clone,inherited,False),'vent-wear-source',name='content')
                report['sourceBounds']=bounds;noise_reports.append(report)
                return [self.instance([content],'native-vent-wear',script=script)]
        return super().walk_native(node,inherited,mask_mode)


if __name__=='__main__':
    if '--map' in sys.argv:raise SystemExit('A08 adapter owns only A08; do not pass --map')
    generic.api.Candidate=A08Candidate
    sys.argv=[str(HERE/'build-layer.py'),'--map','A08']+sys.argv[1:]
    generic.main()
    out=HERE/'layers/CF6_A08_BG_VectorCandidate01';path=out/'report.json'
    report=json.loads(path.read_text(encoding='utf-8'));report['localProceduralApproximations']=noise_reports
    report['specializedConverterSha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['noiseHelperSha256']=hashlib.sha256((HERE/'procedural_filter.py').read_bytes()).hexdigest()
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (out/'a08-adapter.source.py').write_bytes(Path(__file__).read_bytes());(out/'procedural-filter.source.py').write_bytes((HERE/'procedural_filter.py').read_bytes())
    print('A08 native vent-wear patches:',len(noise_reports),'no generated raster images')
