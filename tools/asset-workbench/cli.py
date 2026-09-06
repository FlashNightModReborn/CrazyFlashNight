"""显式启动的素材工具入口；api 模式只向 stdout 输出一条 JSON。"""
from __future__ import annotations

import argparse
import json
import sys

import core


def main():
    parser = argparse.ArgumentParser(description="物品素材工作台：生成候选、预览、应用及撤回")
    parser.add_argument("command", choices=("catalog", "rescan", "start", "bake", "run", "status", "apply", "undo", "cancel", "api"))
    parser.add_argument("--item")
    parser.add_argument("--kind", choices=core.KINDS, default="all")
    parser.add_argument("--job")
    args = parser.parse_args()
    try:
        if args.command == "api":
            raw = sys.stdin.read(16385)
            if len(raw) > 16384:
                raise core.WorkbenchError("请求过大")
            result = core.api(json.loads(raw))
        elif args.command == "run":
            result = core.run(args.job)
        elif args.command == "bake":
            job = core.start(args.item, args.kind, args.job, detached=False)
            result = core.run(job["jobId"])
        else:
            request = {"op": args.command}
            if args.item is not None:
                request["item"] = args.item
            if args.job is not None:
                request["jobId"] = args.job
            if args.command == "start":
                request["kind"] = args.kind
            result = core.api(request)
        print(json.dumps({"success": True, "data": result}, ensure_ascii=False))
        return 1 if isinstance(result, dict) and result.get("state") == "failed" else 0
    except Exception as error:
        print(json.dumps({"success": False, "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
