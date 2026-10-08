"""Low-cost first-screen tree-crown hulls. Original tree/ship sources are untouched."""
import bmesh
import bpy
import numpy as np


def crown_lod(source_mesh):
    coords = np.empty(len(source_mesh.vertices) * 3, dtype=np.float32)
    source_mesh.vertices.foreach_get('co', coords)
    coords = coords.reshape(-1, 3)
    lo, hi = coords.min(axis=0), coords.max(axis=0)
    mid = (lo + hi) / 2
    overlap = (hi - lo)[:2] * 0.035
    all_vertices, all_faces = [], []
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            mask = (sx * (coords[:, 0] - mid[0]) >= -overlap[0]) & (sy * (coords[:, 1] - mid[1]) >= -overlap[1])
            part = coords[mask]
            if len(part) < 8:
                continue
            # Keep extrema, then a bounded deterministic sample; no new canopy extent.
            indices = np.unique(np.concatenate([np.linspace(0, len(part) - 1, min(160, len(part)), dtype=np.int64),
                                                 np.argmin(part, axis=0), np.argmax(part, axis=0)]))
            points = np.unique(part[indices], axis=0)
            bm = bmesh.new()
            for point in points:
                bm.verts.new(point.tolist())
            bm.verts.ensure_lookup_table()
            try:
                bmesh.ops.convex_hull(bm, input=list(bm.verts), use_existing_faces=False)
                bmesh.ops.triangulate(bm, faces=list(bm.faces))
                bm.verts.index_update()
                used = sorted({v for face in bm.faces for v in face.verts}, key=lambda v: v.index)
                offset = len(all_vertices)
                index = {v: offset + i for i, v in enumerate(used)}
                all_vertices.extend([tuple(v.co) for v in used])
                all_faces.extend([tuple(index[v] for v in face.verts) for face in bm.faces])
            finally:
                bm.free()
    if not all_faces:
        raise RuntimeError('Could not derive canopy hull: ' + source_mesh.name)
    result = bpy.data.meshes.new('RUNTIME_LOD_' + source_mesh.name)
    result.from_pydata(all_vertices, [], all_faces)
    result.update()
    # Crown templates use their source leaf material. No new palette or image is made.
    for material in source_mesh.materials:
        result.materials.append(material)
    if len(source_mesh.materials) > 1:
        counts = np.bincount([polygon.material_index for polygon in source_mesh.polygons], minlength=len(source_mesh.materials))
        dominant = int(counts.argmax())
        for polygon in result.polygons:
            polygon.material_index = dominant
    return result
