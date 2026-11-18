"""Assemble the authored A07 Roadster XFL and bind its existing playback routes."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

PROFILE = Path(__file__).with_name("roadster-profile.json")
NS = "http://ns.adobe.com/xfl/2008/"
N = "{" + NS + "}"
ET.register_namespace("", NS)


def read_profile():
    profile = json.loads(PROFILE.read_text(encoding="utf-8"))
    if profile["schema"] != "cf6-a07-roadster.v1":
        raise ValueError("Unexpected A07 roadster profile")
    return profile


def parse_xml(raw: bytes):
    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("DTD/entities are not accepted in asset XML")
    if b"<?XML-STYLESHEET" in raw.upper():
        raise ValueError("External XML stylesheet processing is not accepted")
    return ET.fromstring(raw)


def xml_bytes(tree) -> bytes:
    ET.indent(tree, space="  ")
    return ET.tostring(tree, encoding="utf-8", xml_declaration=True) + b"\n"

def element(tag, attrs=None, parent=None):
    node = ET.Element(N + tag, {k: str(v) for k, v in (attrs or {}).items()})
    if parent is not None:
        parent.append(node)
    return node

def make_layer(parent, name):
    return element("frames", parent=element("DOMLayer", {"name": name, "color": "#4FFF4F"}, parent))


def make_frame(parent, index=0, duration=1, *, stop=False):
    frame = element("DOMFrame", {"index": index, "duration": duration, "keyMode": 9728}, parent)
    if stop:
        element("script", parent=element("Actionscript", parent=frame)).text = "stop();"
    return element("elements", parent=frame)


def instance(name, *, kind="graphic", instance_name=None):
    attrs = {"libraryItemName": name, "symbolType": kind}
    if kind == "graphic":
        attrs.update(loop="single frame", firstFrame="0")
    if instance_name:
        attrs["name"] = instance_name
    return element("DOMSymbolInstance", attrs)

def layers_of(symbol):
    return symbol.find(N + "timeline/" + N + "DOMTimeline/" + N + "layers")


def placements(document):
    return {item.get("libraryItemName") for item in document.iter(N + "DOMSymbolInstance")}


def include_closure(project, roadster, entry):
    """Copy only the needed symbol DAG, leaving the other project's library IDs alone."""
    document = parse_xml(project["DOMDocument.xml"])
    includes = document.find(N + "symbols")
    folders = document.find(N + "folders")
    if folders is None:
        folders = element("folders")
        document.insert(list(document).index(includes), folders)
    known_folders = {row.get("name") for row in folders}
    known_files = {row.get("href").casefold() for row in includes}
    needed = set()
    pending = [entry]
    while pending:
        name = pending.pop()
        if name not in needed:
            needed.add(name)
            pending.extend(placements(parse_xml(roadster[name + ".xml"])))
    for name in sorted(needed):
        href = name + ".xml"
        if href.casefold() in known_files:
            raise ValueError("Library collision: " + href)
        for depth in range(1, len(name.split("/"))):
            folder = "/".join(name.split("/")[:depth])
            if folder not in known_folders:
                element("DOMFolderItem", {"name": folder}, folders)
                known_folders.add(folder)
        element("Include", {"href": href, "loadImmediate": "false"}, includes)
        project["LIBRARY/" + href] = roadster[href]
    project["DOMDocument.xml"] = xml_bytes(document)
    return len(needed)


def install_a07(project, roadster, profile):
    body_path, player_path = ("LIBRARY/CF6VehicleSource/" + n + ".xml" for n in ("1801", "1803"))
    body, player = (parse_xml(project[path]) for path in (body_path, player_path))
    body_layers = layers_of(body)
    old_body = {layer.get("name"): layer for layer in body_layers}
    if set(old_body) != {"source_depth_1", "source_depth_2", "source_depth_4", "controlled_timeline"}:
        raise ValueError("A07 original body layer contract changed")
    body_frames = old_body["source_depth_1"].find(N + "frames")
    body_shifts = [float(frame.find(".//" + N + "Matrix").get("tx")) for frame in body_frames]
    player_layer = next(layer for layer in layers_of(player) if layer.get("name") == "source_depth_1")
    player_frames = player_layer.find(N + "frames")
    vehicle_places = list(player_frames.iter(N + "DOMSymbolInstance"))
    if len(player_frames) != 29 or len(vehicle_places) != 29 or len({
            (tuple(place.attrib.items()), tuple(place.find(".//" + N + "Matrix").attrib.items()))
            for place in vehicle_places}) != 1 or vehicle_places[0].get("name") != "p1":
        raise ValueError("A07 car tracking layer is no longer a constant placement")
    holder_y = float(vehicle_places[0].find(".//" + N + "Matrix").get("ty"))
    player_frames[0].set("duration", str(len(player_frames)))
    del player_frames[1:]

    for name in ("source_depth_1", "source_depth_2", "source_depth_4"):
        body_layers.remove(old_body[name])
    visual = instance(profile["visual_symbol"], kind="movie clip", instance_name="roadster")
    fitted = profile["fitted_player_matrix"].copy()
    fitted[5] -= holder_y
    element("Matrix", dict(zip(("a", "b", "c", "d", "tx", "ty"), fitted)),
            element("matrix", parent=visual))
    make_frame(make_layer(body_layers, "roadster_visual"), duration=len(body_shifts)).append(visual)
    # Carry over the authored body recoil on hit without re-placing the animated clip.
    scripts = list(old_body["controlled_timeline"].iter(N + "script"))
    if len(scripts) != len(body_shifts):
        raise ValueError("A07 hit timeline frames and artwork diverged")
    for script, shift in zip(scripts, body_shifts):
        script.text += f"roadster._x={fitted[4] + shift:.12g};"
    project[body_path], project[player_path] = xml_bytes(body), xml_bytes(player)
    include_count = include_closure(project, roadster, profile["visual_symbol"])
    return {"fitted_player_matrix": profile["fitted_player_matrix"],
            "preserved_body_shifts": body_shifts, "roadster_symbol_count": include_count,
            "wheel_blur_overlays": profile["wheel_blur_overlays"]}

def road_steps(road_xml: bytes):
    road = parse_xml(road_xml)
    asphalt = next(layer for layer in road.iter(N + "DOMLayer") if layer.get("name") == "source_depth_18")
    x = [float(row.get("tx")) for row in asphalt.iter(N + "Matrix")]
    deltas = [round(b - a, 2) for a, b in zip(x, x[1:])]
    if len(x) != 49 or any(not -20 < distance < -18 for distance in deltas):
        raise ValueError("Inspect changed A07 asphalt scrolling frames")
    # The last -> first transition is a visual tile reset. Use the authored
    # physical step through that tick rather than interpreting the reset as travel.
    return deltas + [round(sum(deltas) / len(deltas), 2)]

def render_driver(template, profile, road_xml):
    config = profile["clock_config"]
    binding = profile["bindings"]
    overlays = profile["wheel_blur_overlays"]
    wheels = {row["instance"] for row in binding["controlled_parts"] if row["clock"] == "wheels"}
    if len(overlays) != 4 or not overlays.keys() <= wheels:
        raise ValueError("A07 wheel overlays do not match the authored motion routes")
    routes = [[row["instance"], binding["pose_frame_fields"][row["clock"]], overlays.get(row["instance"])]
              for row in binding["controlled_parts"]]
    values = {
        "__ROADSTER_CLOCK_CONFIG__": "{" + ",".join(f"{k}:{v}" for k, v in config.items()) + "}",
        "__ROADSTER_PART_ROUTES__": json.dumps(routes, separators=(",", ":")),
        "__ROADSTER_ASPHALT_STEPS__": json.dumps(road_steps(road_xml), separators=(",", ":")),
        "__ROADSTER_WHEEL_BLUR_ENABLED__": "true",
    }
    for marker, value in values.items():
        if template.count(marker) != 1:
            raise ValueError("A07 roadster presentation template changed: " + marker)
        template = template.replace(marker, value)
    return template
