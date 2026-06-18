#!/usr/bin/env python
from __future__ import annotations

import json

from asset_timeline_export import FrameDedupeIndex, compressed_timeline_entries


def main() -> None:
    dedupe = FrameDedupeIndex()
    first = dedupe.resolve("digest-a", 1, "asset_1.png")
    second = dedupe.resolve("digest-b", 2, "asset_2.png")
    third = dedupe.resolve("digest-a", 3, "asset_3.png")

    icon_frames = [
        {"frame": 1, "sourceFrame": 1, "uri": "a.png"},
        {"frame": 2, "sourceFrame": 2, "uri": "a.png", "duplicateOfFrame": 1},
        {"frame": 3, "sourceFrame": 3, "uri": "b.png"},
        {"frame": 4, "sourceFrame": 4, "uri": "b.png", "duplicateOfFrame": 3},
    ]
    icon_timeline = compressed_timeline_entries(icon_frames)

    dressup_frames = [
        {"frame": 1, "sourceFrame": 1, "uri": "same.png", "width": 10, "height": 10, "originX": 0, "originY": 0},
        {"frame": 2, "sourceFrame": 2, "uri": "same.png", "width": 10, "height": 10, "originX": 0, "originY": 0},
        {"frame": 3, "sourceFrame": 3, "uri": "same.png", "width": 10, "height": 10, "originX": 2, "originY": 0},
        {"frame": 4, "sourceFrame": 4, "uri": "same.png", "width": 10, "height": 10, "originX": 2, "originY": 0},
    ]
    report: dict[str, object] = {}
    dressup_timeline = compressed_timeline_entries(
        dressup_frames,
        report,
        owner="skin",
        identity_keys=("uri", "width", "height", "originX", "originY"),
    )
    uri_only_timeline = compressed_timeline_entries(dressup_frames)

    payload = {
        "dedupe": {
            "first": first.__dict__,
            "second": second.__dict__,
            "third": third.__dict__,
            "uniqueCount": dedupe.unique_count,
        },
        "iconTimeline": icon_timeline,
        "dressupTimeline": dressup_timeline,
        "uriOnlyTimeline": uri_only_timeline,
        "report": report,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))

    assert first.filename == "asset_1.png" and not first.is_duplicate
    assert second.filename == "asset_2.png" and not second.is_duplicate
    assert third.filename == "asset_1.png" and third.duplicate_of_frame == 1 and third.is_duplicate
    assert dedupe.unique_count == 2
    assert len(icon_timeline) == 2
    assert icon_timeline[0]["durationFrames"] == 2
    assert icon_timeline[0]["frameEnd"] == 2
    assert len(dressup_timeline) == 2
    assert dressup_timeline[0]["durationFrames"] == 2
    assert dressup_timeline[1]["durationFrames"] == 2
    assert len(uri_only_timeline) == 1
    assert uri_only_timeline[0]["durationFrames"] == 4
    assert report["timelineLogicalFrames"] == 4
    assert report["timelineFrameEntries"] == 2
    assert report["timelineCompressedFrameRefs"] == 2


if __name__ == "__main__":
    main()
