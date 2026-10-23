"""Art-only timeline contracts against the actual immutable source frame data."""
import copy
import json
import math
from pathlib import Path
import unittest
from pod_scale import calibrate_frames

ROOT=Path(__file__).resolve().parents[2]

class PodScale(unittest.TestCase):
    def setUp(self):
        path=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A15-R2/cf6-stage15-redraw-r2/reference/environment-original-nodes.json'
        data=json.loads(path.read_text(encoding='utf-8'))
        self.nodes=data.get('nodes',data)
        self.policy=json.loads((ROOT/'tools/cf6-prop-layout/scale-policy.json').read_text(encoding='utf-8'))['pod']

    def test_growth_removed_without_mutating_source_or_markers(self):
        before=copy.deepcopy(self.nodes)
        frames,audit=calibrate_frames(self.nodes,self.policy)
        self.assertEqual(before,self.nodes)
        self.assertEqual(len(frames),25)
        self.assertEqual(frames[23:],self.nodes['1939']['frames'][23:])
        norms=[r['referenceLimbNormAfter'] for r in audit if r['referenceLimbNormAfter'] is not None]
        self.assertLess(max(norms)-min(norms),1e-8)
        feet=[r['targetFootY'] for r in audit[:23]]
        self.assertEqual(len(set(feet[:7])),1)
        self.assertTrue(all(b>=a for a,b in zip(feet,feet[1:])))
        self.assertLess(max(b-a for a,b in zip(feet,feet[1:])),5.6)
        self.assertAlmostEqual(feet[-1],self.policy['bodyFootTrajectory']['targetFootY'])
        for old,new in zip(self.nodes['1939']['frames'][:1],frames[:1]):
            for depth,row in old.items():
                if row['id']==1906:
                    from pod_scale import about_pivot
                    expected=about_pivot(row['matrix'],self.policy['initialScale'],[-7,8])
                    for a,b in zip(new[depth]['matrix'],expected):self.assertAlmostEqual(a,b)
        for old,new in zip(self.nodes['1939']['frames'],frames):
            self.assertEqual(list(old),list(new))
            for depth,row in old.items():
                if row['id'] in {277,359,360,1433}:self.assertEqual(row,new[depth])
                self.assertEqual({k:v for k,v in row.items() if k!='matrix'}, {k:v for k,v in new[depth].items() if k!='matrix'})

    def test_unreviewed_timeline_part_or_anchor_rejected(self):
        self.nodes['1939']['frames'][0]['unreviewed']={'id':999999,'matrix':[1,0,0,1,0,0]}
        with self.assertRaises(ValueError):calibrate_frames(self.nodes,self.policy)
        del self.nodes['1939']['frames'][0]['unreviewed']
        self.policy['containerPivot']=[0,0]
        with self.assertRaises(ValueError):calibrate_frames(self.nodes,self.policy)

if __name__=='__main__':unittest.main()
