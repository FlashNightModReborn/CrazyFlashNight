"""Decode the frozen Animate 03/05 DAT cache into portable PNG editing inputs.

DAT stores premultiplied ARGB rows, either raw or a length-prefixed zlib stream.
Keep both real PNG editing inputs and validated compact Adobe caches.
"""
import io
import struct
import zlib
from PIL import Image


def unpack(data,expected_width=None,expected_height=None):
    if len(data)<26 or data[:2]!=b"\x03\x05":
        raise ValueError("Unsupported artist bitmap cache")
    stride,width,height=struct.unpack_from("<3H",data,2)
    if stride!=width*4 or width<1 or height<1 or data[24]!=1:
        raise ValueError("Unsupported DAT pixel layout")
    if expected_width is not None and (width,height)!=(expected_width,expected_height):
        raise ValueError("DAT dimensions differ from its frozen media declaration")
    if data[25]==0:
        pixels=data[26:]
    elif data[25]==1:
        chunks=[];pos=26
        while True:
            if pos+2>len(data):raise ValueError("Truncated DAT chunk header")
            size=struct.unpack_from("<H",data,pos)[0];pos+=2
            if not size:break
            if pos+size>len(data):raise ValueError("Truncated DAT compressed chunk")
            chunks.append(data[pos:pos+size]);pos+=size
        if pos!=len(data):raise ValueError("Unexpected bytes after DAT terminator")
        stream=zlib.decompressobj()
        pixels=stream.decompress(b"".join(chunks))+stream.flush()
        if not stream.eof or stream.unused_data:
            raise ValueError("DAT zlib stream is incomplete or ambiguous")
    else:
        raise ValueError("Unsupported DAT compression flag")
    if len(pixels)!=stride*height:
        raise ValueError("DAT decoded byte length mismatch")
    return width,height,pixels


def decode(data,expected_width=None,expected_height=None):
    width,height,pixels=unpack(data,expected_width,expected_height)
    # Adobe stores alpha first and premultiplies the three color channels.
    rgba=bytearray(len(pixels))
    for i in range(0,len(pixels),4):
        a,r,g,b=pixels[i:i+4]
        if max(r,g,b)>a:raise ValueError("DAT is not the expected premultiplied ARGB")
        if a and a!=255:
            r=min(255,(r*255+a//2)//a);g=min(255,(g*255+a//2)//a);b=min(255,(b*255+a//2)//a)
        rgba[i:i+4]=bytes((r,g,b,a))
    return Image.frombytes("RGBA",(width,height),bytes(rgba))


def cache(data,width,height):
    _,_,pixels=unpack(data,width,height)
    packed=zlib.compress(pixels,9)
    chunks=[packed[i:i+2048] for i in range(0,len(packed),2048)]
    return data[:25]+b"\x01"+b"".join(struct.pack("<H",len(c))+c for c in chunks)+b"\0\0"


def png(data,width,height):
    image=decode(data,width,height)
    output=io.BytesIO()
    image.save(output,format="PNG",compress_level=9)
    return output.getvalue()
