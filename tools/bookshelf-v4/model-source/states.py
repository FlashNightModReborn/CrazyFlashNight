"""Reversible Blender preview states. No animation clips and no game logic."""
import bpy

def remember_rest():
    for o in bpy.context.scene.objects:
        if 'pullAxis' in o:
            o['restLocation']=list(o.location)

def reset():
    for o in bpy.context.scene.objects:
        if 'restLocation' in o:
            o.location=o['restLocation']

def pull(name, amount):
    o=bpy.data.objects[name]
    if 'restLocation' not in o:o['restLocation']=list(o.location)
    amount=max(0,min(float(amount),1))
    o.location=o['restLocation']
    o.location.y-=amount*float(o['pullMax'])

def apply_state(state):
    reset()
    if state=='archives-open':pull('ARCHIVE_ALL_DRAWER',1)
    elif state=='collection-pulled':pull('COLLECTION_CF1_6',.65)
    elif state=='disc-pulled':pull('COLLECTION_CF1_6',.45);pull('DISC_CF3',.7)
    elif state=='book-pulled':pull('BOOK_babylon',.75)
    elif state!='default':raise ValueError(state)
