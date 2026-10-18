"""Build unit-private debris prefabs from the owned vector rig, with no new linkage exports."""

def fragment_layer(native, result, parts, rows, name, start, total, splits=None):
    usable = [row for _, row in sorted(rows.items(), key=lambda item: int(item[0])) if row['id'] in parts]
    elements = []
    fragments = []
    for row in usable:
        m = list(row['matrix'])
        for piece in (splits or {}).get(row['id'],[{'name':parts[row['id']], 'center':[0,0]}]):
            x,y = piece['center']
            fragments.append((piece['name'],[m[0],m[1],m[2],m[3],m[4]+m[0]*x+m[2]*y,m[5]+m[1]*x+m[3]*y]))
    for i, (part_name,m) in enumerate(fragments, 1):
        fragment = name+'/分件'+str(i)
        result[fragment] = native.symbol(fragment, [native.layer('原始分件', [native.frame(elements=[
            native.instance(part_name, matrix=(m[0],m[1],m[2],m[3],0,0))])])], symbol_type='movie clip')
        elements.append(native.instance(fragment, matrix=(1,0,0,1,m[4],m[5]), symbol_type='movie clip', name='碎片'+str(i)))
    result[name] = native.symbol(name, [native.layer('预制碎片', [native.frame(elements=elements, script='stop();')])], symbol_type='movie clip')
    return native.make_sparse_layer('物理碎片', total, {start: {'duration': total-start, 'elements': [native.instance(
        name, symbol_type='movie clip', name='尸体碎片',
        script='onClipEvent(load){_parent._parent.cf6StartCorpseFragments(this,'+str(len(fragments))+');}')]}})
