"""共享路径设置 — 复用 mercenary-ai-sim 的碰撞检测和地图模型。"""
import sys
import os

# 确保本地目录优先（避免 mercenary-ai-sim 的同名模块覆盖）
_local_dir = os.path.dirname(os.path.abspath(__file__))
if _local_dir not in sys.path:
    sys.path.insert(0, _local_dir)

_sim_dir = os.path.join(os.path.dirname(__file__), "..", "mercenary-ai-sim")
if _sim_dir not in sys.path:
    sys.path.append(_sim_dir)  # append 而非 insert，本地优先

# re-export for convenience
from collision import CollisionWorld, NavigationGrid  # noqa: F401,E402
from map_model import MapData, generate_adversarial_map, generate_random_map  # noqa: F401,E402
from map_model import load_real_maps, place_doors_on_bounds  # noqa: F401,E402
