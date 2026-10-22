"""Measure only rendered subject pixels, and keep source-relative feature anchors."""
from PIL import Image, ImageChops, ImageStat
import hashlib

active=None


def begin(entry):
    global active
    active={"entry":entry,"mask":Image.new("L",(644,276),0),"layers":[]}


def record(scaled,x,y):
    if active is None:return
    layer=Image.new("RGBA",(644,276),(0,0,0,0));layer.alpha_composite(scaled,(x,y))
    solid=layer.getchannel("A").point(lambda a:255 if a>=220 else 0)
    active["mask"]=ImageChops.lighter(active["mask"],solid)
    active["layers"].append({"x":x,"y":y,"width":scaled.width,"height":scaled.height})


def finish(image,output):
    global active
    if active is None:return None
    context=active;active=None
    if not context["layers"]:return None
    mask=context["mask"];stats=ImageStat.Stat(image.convert("L"),mask)
    entry=context["entry"];folder=output/"masks";folder.mkdir(exist_ok=True);file=folder/(entry["id"]+".png");mask.save(file)
    features=[]
    for point in entry.get("requiredSubjectPoints",[]):
        layer=context["layers"][point.get("layer",0)];u,v=point["uv"]
        x=layer["x"]+u*layer["width"];y=layer["y"]+v*layer["height"]
        margin=point.get("margin",8)
        features.append({"name":point["name"],"x":x,"y":y,"inside":margin<=x<644-margin and margin<=y<276-margin})
    return {"file":file.relative_to(output).as_posix(),"sha256":hashlib.sha256(file.read_bytes()).hexdigest(),
            "pixels":stats.count[0],"mean":stats.mean[0],"std":stats.stddev[0],"layers":context["layers"],"features":features}
