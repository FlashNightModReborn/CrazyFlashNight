"""Bounded native runtime substitute for A08's eight tiny vent-wear noise patches.

This is an explicitly approximate Flash Perlin implementation, not an SVG pixel
equivalence claim. No image file is created; the vector silhouette stays editable.
"""
import json
import math


def local_tag(node):return node.tag.split('}')[-1]


def vent_wear(filter_node):
    rows=list(filter_node)
    if [local_tag(row) for row in rows]!=['feTurbulence','feColorMatrix','feComposite']:
        raise ValueError('only the isolated vent-wear graph is supported')
    turbulence,color,composite=rows
    if filter_node.get('color-interpolation-filters')!='sRGB' or turbulence.get('type','turbulence')!='turbulence' or turbulence.get('stitchTiles','noStitch')!='noStitch':
        raise ValueError('unexpected noise/color mode')
    result=turbulence.get('result')
    if not result or color.get('in')!=result or color.get('type','matrix')!='matrix' or composite.get('operator')!='in' or composite.get('in2')!='SourceGraphic':
        raise ValueError('unexpected noise filter wiring')
    if composite.get('in') is not None:raise ValueError('composite must consume the preceding matrix')
    frequency=[float(x) for x in turbulence.get('baseFrequency','').split()]
    if len(frequency)==1:frequency*=2
    if len(frequency)!=2 or not all(math.isfinite(x) and 0<x<=1 for x in frequency):raise ValueError('unsupported frequency')
    octaves=int(turbulence.get('numOctaves','1'));seed=int(turbulence.get('seed','0'))
    if not 1<=octaves<=4 or not 0<=seed<2147483647:raise ValueError('noise octave/seed outside bounded scope')
    values=[float(x) for x in color.get('values','').split()]
    expected=[0,0,0,0,.2,0,0,0,0,.2,0,0,0,0,.18,.9,0,0,0,-.32]
    if values!=expected:raise ValueError('only the reviewed vent-wear color matrix is supported')
    native=[value*255 if i%5==4 else value for i,value in enumerate(values)]
    offsets=','.join('new flash.geom.Point(left,top)' for _ in range(octaves))
    script='''stop();
var bounds=content.getBounds(this);
var left=Math.floor(bounds.xMin),top=Math.floor(bounds.yMin);
var width=Math.ceil(bounds.xMax)-left,height=Math.ceil(bounds.yMax)-top;
if(width>0 && height>0 && width<=512 && height<=128) {
  this.__cf6NoiseBitmap=new flash.display.BitmapData(width,height,true,0xFF000000);
  this.__cf6NoiseBitmap.perlinNoise(%s,%s,%d,%d,false,false,1,true,[%s]);
  this.__cf6NoiseBitmap.applyFilter(this.__cf6NoiseBitmap,new flash.geom.Rectangle(0,0,width,height),new flash.geom.Point(0,0),new flash.filters.ColorMatrixFilter(%s));
  var noise=this.createEmptyMovieClip("nativeVentWear",this.getNextHighestDepth());
  noise._x=left;noise._y=top;noise.attachBitmap(this.__cf6NoiseBitmap,0,"auto",true);
  content.cacheAsBitmap=true;noise.cacheAsBitmap=true;noise.setMask(content);
  this.onUnload=function(){this.__cf6NoiseBitmap.dispose();};
} else {trace("CF6_VECTOR_VENT_NOISE_BOUNDS_UNSUPPORTED");}
'''%(1/frequency[0],1/frequency[1],octaves,seed,offsets,json.dumps(native,separators=(',',':')))
    report={'id':filter_node.get('id'),'scope':'A08 isolated vent-wear overlay only; source vector silhouette retained',
            'sourceFrequency':frequency,'sourceOctaves':octaves,'sourceSeed':seed,'nativeBaseSize':[1/frequency[0],1/frequency[1]],
            'maxRuntimePixels':[512,128],'nativeColorMatrix':native,
            'difference':'Flash perlinNoise and SVG feTurbulence need not yield identical grain; local approximation requires visual comparison',
            'storage':'runtime-only bounded BitmapData; no generated PNG and no whole-layer flattening'}
    return script,report
