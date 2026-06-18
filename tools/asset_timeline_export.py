from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Sequence


@dataclass(frozen=True)
class DedupeFrameRef:
    filename: str
    duplicate_of_frame: int | None
    is_duplicate: bool


class FrameDedupeIndex:
    def __init__(self) -> None:
        self._digest_to_file: dict[str, str] = {}
        self._digest_to_frame: dict[str, int] = {}

    @property
    def unique_count(self) -> int:
        return len(self._digest_to_file)

    def resolve(self, digest: str, frame_index: int, unique_filename: str) -> DedupeFrameRef:
        duplicate_of_frame = self._digest_to_frame.get(digest)
        if duplicate_of_frame is not None:
            return DedupeFrameRef(
                filename=self._digest_to_file[digest],
                duplicate_of_frame=duplicate_of_frame,
                is_duplicate=True,
            )

        self._digest_to_file[digest] = unique_filename
        self._digest_to_frame[digest] = frame_index
        return DedupeFrameRef(
            filename=unique_filename,
            duplicate_of_frame=None,
            is_duplicate=False,
        )


def frame_display_key(
    frame_entry: dict[str, Any],
    identity_keys: Sequence[str] = ("uri",),
) -> tuple[Any, ...]:
    return tuple(frame_entry.get(key) for key in identity_keys)


def compressed_timeline_entries(
    frame_entries: list[dict[str, Any]],
    export_report: dict[str, Any] | None = None,
    owner: str | None = None,
    identity_keys: Sequence[str] = ("uri",),
) -> list[dict[str, Any]]:
    timeline: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    current_key: tuple[Any, ...] | None = None

    for frame_entry in frame_entries:
        display_key = frame_display_key(frame_entry, identity_keys)
        if current is not None and display_key == current_key:
            current["durationFrames"] = int(current.get("durationFrames") or 1) + 1
            current["frameEnd"] = frame_entry.get("frame")
            current["sourceFrameEnd"] = frame_entry.get("sourceFrame", frame_entry.get("frame"))
            continue

        current = dict(frame_entry)
        current_key = display_key
        timeline.append(current)

    for entry in timeline:
        if int(entry.get("durationFrames") or 1) <= 1:
            entry.pop("durationFrames", None)
            entry.pop("frameEnd", None)
            entry.pop("sourceFrameEnd", None)

    if export_report is not None:
        export_report["timelineLogicalFrames"] = export_report.get("timelineLogicalFrames", 0) + len(frame_entries)
        export_report["timelineFrameEntries"] = export_report.get("timelineFrameEntries", 0) + len(timeline)
        saved = len(frame_entries) - len(timeline)
        export_report["timelineCompressedFrameRefs"] = (
            export_report.get("timelineCompressedFrameRefs", 0) + saved
        )
        if saved > 0:
            longest_hold = max(int(entry.get("durationFrames") or 1) for entry in timeline)
            samples = export_report.setdefault("timelineCompressionSamples", [])
            samples.append(
                {
                    "owner": owner,
                    "logicalFrames": len(frame_entries),
                    "timelineFrames": len(timeline),
                    "savedFrameEntries": saved,
                    "uniqueUris": len({entry.get("uri") for entry in frame_entries}),
                    "longestHoldFrames": longest_hold,
                }
            )

    return timeline
