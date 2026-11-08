"""Compile the loot regression in the real pickup prefab's RSL consumer scope."""
from pathlib import Path
import importlib.util
import sys

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'tools/cf6-soldier-assets'
sys.path.insert(0,str(SOURCE))
spec=importlib.util.spec_from_file_location('cf6_pickup_asset_host',SOURCE/'build-test-consumer.py')
host=importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
host.NAME='Cf6SoldierLootHost'
host.OWNER=ROOT/'scripts'/host.NAME
host.IMPORTS={'可拾取物2':'flashswf/arts/things.swf'}
host.main('loot-pickup-host-manifest.json',550,400)
