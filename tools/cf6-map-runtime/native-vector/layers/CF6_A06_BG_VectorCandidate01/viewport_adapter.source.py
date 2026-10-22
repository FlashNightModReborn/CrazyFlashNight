"""Isolated fix candidate for the exact A05/A06 nested SVG viewport contract."""
import copy
import math


def viewport_matrix(node):
    if node.get('preserveAspectRatio')!='none' or node.get('overflow')!='visible':
        raise ValueError('diagnostic viewport adapter supports reviewed none/visible only')
    values=[float(v) for v in node.get('viewBox','').replace(',',' ').split()]
    if len(values)!=4:raise ValueError('nested SVG requires an explicit viewBox')
    left,top,width,height=values
    x=float(node.get('x','0'));y=float(node.get('y','0'))
    target_width=float(node.get('width'));target_height=float(node.get('height'))
    if not all(math.isfinite(v) for v in values+[x,y,target_width,target_height]) or min(width,height,target_width,target_height)<=0:
        raise ValueError('invalid nested SVG viewport dimensions')
    sx=target_width/width;sy=target_height/height
    return sx,0,0,sy,x-left*sx,y-top*sy


def candidate_class(api):
    class ViewportCandidate(api.Candidate):
        def walk_native(self,node,inherited=None,mask_mode=False):
            if api.tag(node)=='svg' and node is not self.root and node.get('width') is not None:
                placement=viewport_matrix(node)
                clone=copy.deepcopy(node);clone.tag='{http://www.w3.org/2000/svg}g'
                transform=api.base.transform(clone.attrib.pop('transform',None))
                for key in ('x','y','width','height','viewBox','preserveAspectRatio','overflow'):clone.attrib.pop(key,None)
                content=super().walk_native(clone,inherited,mask_mode)
                if not hasattr(self,'viewport_reports'):self.viewport_reports=[]
                self.viewport_reports.append({'id':node.get('id'),'viewBox':node.get('viewBox'),'width':node.get('width'),'height':node.get('height'),'matrix':placement,'overflow':'visible'})
                return [self.instance(content,'nested-svg-viewport',api.base.mul(transform,placement))]
            return super().walk_native(node,inherited,mask_mode)
    return ViewportCandidate
