"""Render only approved door components from archived original timeline metadata.

This module never imports source package Python (which has authoring side effects).
Original actor/weapon/collision markers are excluded by an explicit root whitelist.
"""
from pathlib import Path
import hashlib
import json
import re
from lxml import etree as E

ROOT=Path(__file__).resolve().parents[2]
ARCHIVE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'
SVG='http://www.w3.org/2000/svg'


class DoorArt:
    def __init__(self,package):
        self.package=package
        self.nodes=json.loads((package/'reference/environment-original-nodes.json').read_text(encoding='utf-8'))['nodes']
        self.counter=0
        self.inputs={}

    def record(self,path):
        self.inputs[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()

    def prefixed(self,text,prefix):
        ids=re.findall(r'\bid="([^"]+)"',text)
        for value in sorted(ids,key=len,reverse=True):
            text=text.replace('id="'+value+'"','id="'+prefix+value+'"').replace('url(#'+value+')','url(#'+prefix+value+')')
            text=text.replace('href="#'+value+'"','href="#'+prefix+value+'"')
        return text

    def node(self,cid,frame=1,root_whitelist=None):
        self.counter+=1;prefix='n'+str(self.counter)+'_'
        node=self.nodes[str(cid)]
        if node['code']!=39:
            replacement=self.package/'parts'/('shape-'+str(cid)+'.svg')
            if replacement.is_file():
                self.record(replacement);doc=E.parse(str(replacement))
                text=''.join(E.tostring(child,encoding='unicode') for child in doc.getroot())
            else:text=node['svgInner']
            return self.prefixed(text,prefix)
        rows=node['frames'][(frame-1)%len(node['frames'])];parts=[];masks=[]
        for depth,placement in sorted(rows.items(),key=lambda entry:int(entry[0])):
            depth=int(depth);masks=[m for m in masks if depth<=m[0]]
            if root_whitelist is not None and placement['id'] not in root_whitelist:continue
            if placement.get('name')=='area':continue
            mult=placement.get('colorMult',[256]*4);offset=placement.get('colorAdd',[0]*4)
            if mult[3]==0 and offset[3]==0:continue
            content=self.node(placement['id'],frame-placement['placedAt']+1)
            if mult!=[256]*4 or offset!=[0]*4:
                self.counter+=1;filter_id='color'+str(self.counter)
                content='<defs><filter id="'+filter_id+'" color-interpolation-filters="sRGB"><feComponentTransfer>'+''.join(
                    '<feFunc'+channel+' type="linear" slope="'+str(mult[index]/256)+'" intercept="'+str(offset[index]/255)+'"/>'
                    for index,channel in enumerate('RGBA'))+'</feComponentTransfer></filter></defs><g filter="url(#'+filter_id+')">'+content+'</g>'
            content='<g transform="matrix('+ ' '.join(str(v) for v in placement['matrix'])+')">'+content+'</g>'
            if 'clipDepth' in placement:
                self.counter+=1;mask_id='mask'+str(self.counter);filter_id='white'+str(self.counter)
                parts.append('<defs><filter id="'+filter_id+'"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter><mask id="'+mask_id+'" maskUnits="userSpaceOnUse" x="-5000" y="-5000" width="10000" height="10000"><g filter="url(#'+filter_id+')">'+content+'</g></mask></defs>')
                masks.append((placement['clipDepth'],mask_id));continue
            for _,mask_id in masks:content='<g mask="url(#'+mask_id+')">'+content+'</g>'
            parts.append(content)
        return ''.join(parts)

    def frame(self,cid,index,viewbox,whitelist=None):
        self.counter=0
        self.record(self.package/'reference/environment-original-nodes.json')
        return '<svg xmlns="'+SVG+'" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="'+' '.join(str(v) for v in viewbox)+'">'+self.node(cid,index,whitelist)+'</svg>\n'
