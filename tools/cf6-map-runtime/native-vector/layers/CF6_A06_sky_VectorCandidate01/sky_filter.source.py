"""Bounded runtime approximations for the two authored A02 sky filter graphs."""
import json
import math


def tag(n):return n.tag.split('}')[-1]


def sky_effect(node):
    if node.get('color-interpolation-filters','linearRGB')!='linearRGB':raise ValueError('changed sky filter color space')
    rows=list(node);names=[tag(n) for n in rows];kind=node.get('id')
    if kind=='cloudsoft':
        if names!=['feTurbulence','feDisplacementMap','feGaussianBlur']:raise ValueError('changed cloud graph')
        noise,displace,blur=rows
        if noise.attrib!={'baseFrequency':'.035 .06','numOctaves':'3','seed':'18','result':'noise'} or displace.attrib!={'in':'SourceGraphic','in2':'noise','scale':'10','xChannelSelector':'R','yChannelSelector':'G'} or blur.attrib!={'stdDeviation':'1.7'}:
            raise ValueError('changed authored cloud parameters')
        frequency=[.035,.06];seed=18;channels=3;gray='false'
        effect='content.filters=[new flash.filters.DisplacementMapFilter(this.__cf6SkyNoise,new flash.geom.Point(left,top),1,2,10,10,"color",0,0),new flash.filters.BlurFilter(3.4,3.4,3)];'
    elif kind=='haze':
        if names!=['feTurbulence','feColorMatrix']:raise ValueError('changed haze graph')
        noise,color=rows
        expected=[0,0,0,0,.88,0,0,0,0,.87,0,0,0,0,.73,.2,0,0,0,0]
        if noise.attrib!={'baseFrequency':'.012 .045','numOctaves':'3','seed':'1595'} or color.get('type')!='matrix' or [float(v) for v in color.get('values','').split()]!=expected:
            raise ValueError('changed authored haze parameters')
        # SVG's default filter space is linear RGB. Constant color channels can
        # be converted exactly; the independent noise algorithm remains approximate.
        values=list(expected)
        for index in (4,9,14):
            v=values[index];values[index]=(12.92*v if v<=.0031308 else 1.055*math.pow(v,1/2.4)-.055)*255
        frequency=[.012,.045];seed=1595;channels=1;gray='true'
        effect='''this.__cf6SkyNoise.applyFilter(this.__cf6SkyNoise,new flash.geom.Rectangle(0,0,width,height),new flash.geom.Point(0,0),new flash.filters.ColorMatrixFilter(%s));
  var haze=this.createEmptyMovieClip("nativeHaze",this.getNextHighestDepth());
  haze._x=left;haze._y=top;haze.attachBitmap(this.__cf6SkyNoise,0,"auto",true);
  content.cacheAsBitmap=true;haze.cacheAsBitmap=true;haze.setMask(content);'''%json.dumps(values,separators=(',',':'))
    else:raise ValueError('unknown sky filter')
    script='''stop();
var bounds=content.getBounds(this);
var left=Math.floor(bounds.xMin),top=Math.floor(bounds.yMin);
var width=Math.ceil(bounds.xMax)-left,height=Math.ceil(bounds.yMax)-top;
if(width>0 && height>0 && width<=1024 && height<=512) {
  this.__cf6SkyNoise=new flash.display.BitmapData(width,height,true,0xFF000000);
  this.__cf6SkyNoise.perlinNoise(%s,%s,3,%d,false,false,%d,%s,[new flash.geom.Point(left,top),new flash.geom.Point(left,top),new flash.geom.Point(left,top)]);
  %s
  this.onUnload=function(){this.__cf6SkyNoise.dispose();};
} else {trace("CF6_SKY_NOISE_BOUNDS_UNSUPPORTED");}
'''%(1/frequency[0],1/frequency[1],seed,channels,gray,effect)
    return script,{'id':kind,'sourceGraph':names,'sourceFrequency':frequency,'sourceSeed':seed,'runtimeLimit':[1024,512],
        'storage':'bounded runtime BitmapData only; vector source retained; no generated PNG',
        'difference':'Flash perlinNoise is not SVG feTurbulence. Cloud displacement/color interpolation and three-pass blur are visual approximations; source filter-region crop is replaced by the explicit sky viewport clip.'}
