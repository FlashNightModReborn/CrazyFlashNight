#!/usr/bin/env python3
"""Build CS6 compile-only classpaths and the three owned loader projects."""
import argparse
import hashlib
import json
from functools import lru_cache
from pathlib import Path
import re
import sys
from asloader_module_api import declaration

ROOT = Path(__file__).resolve().parent.parent
NS = 'http://ns.adobe.com/xfl/2008/'
ORDER = ('resident', 'shared', 'boot')
BOM = b'\xef\xbb\xbf'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def as_bytes(text):
    return BOM + text.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8')

@lru_cache(maxsize=1024)
def projected_declaration(source, fqn, provider):
    # Both foreign modules project the same provider bytes. Reuse the pure
    # computation across captures; changes to the file bytes are part of the key.
    return as_bytes(declaration(source.decode('utf-8-sig').replace('\r\n','\n'), fqn, provider))

def include_fingerprints(root, roots, include_base=None):
    root=root.resolve();inputs={};visited=set()
    def capture(p, base, stack=()):
        p=p.resolve()
        if not p.is_relative_to(root):
            raise ValueError('Boot source escapes repository: '+str(p))
        if p in stack:
            raise ValueError('Cyclic boot include: '+str(p))
        if p in visited:
            return
        visited.add(p)
        raw=p.read_bytes();inputs[p.relative_to(root).as_posix()]=digest(raw)
        text=raw.decode('utf-8-sig')
        text=re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*[\s\S]*?\*/|//[^\r\n]*',
            lambda m:m.group() if m.group()[0] in "\"'" else re.sub(r'[^\r\n]',' ',m.group()),text)
        for match in re.finditer(r'^[ \t]*#include\s+["\']([^"\']+)["\']',text,re.MULTILINE):
            # CS6 resolves nested includes from the XFL include base, just as
            # assemble-collapsed-frame.js does; it does not rebase per AS file.
            capture(base/match.group(1).replace('\\','/'),base,stack+(p,))
    for p in roots:
        capture(p,include_base or p.parent)
    return inputs

def project_paths(catalog):
    paths = {}
    for name in ORDER:
        xfl = Path(catalog[name]['xfl'])
        directory = xfl.parent
        row = {'roots': f'scripts/asLoaderModuleRoots/{name}.as',
               'exclude': (directory/(xfl.stem+'_exclude.xml')).as_posix(),
               'profile': (directory/'PublishSettings.xml').as_posix(),
               'document': (directory/'DOMDocument.xml').as_posix()}
        if name != 'boot':
            row.update(xfl=xfl.as_posix(), mobile=(directory/'MobileSettings.xml').as_posix())
        if name == 'resident':
            row['symbol'] = (directory/'LIBRARY/asLoader.xml').as_posix()
        paths[name] = row
    return paths


def plan(root=ROOT, *, class_sources=None, template_bytes=None):
    if not (root/'scripts/asLoaderBootstrap.as').read_bytes().startswith(BOM):
        raise ValueError('scripts/asLoaderBootstrap.as requires UTF-8 BOM before CS6 inclusion')
    catalog_raw = (root/'tools/asloader-modules.json').read_bytes()
    catalog = json.loads(catalog_raw)
    projects = project_paths(catalog)
    if catalog['schema'] != 'cf7-asloader-modules.v1':
        raise ValueError('Unsupported module catalog')
    owners = {}
    for name in ORDER:
        for fqn in catalog[name]['classes']:
            if fqn in owners:
                raise ValueError('Duplicate class owner: '+fqn)
            owners[fqn] = name
    # A normal loaded SWF owns its SharedObject namespace. Keep the sole save
    # implementation in the original RSL, whose importer is the main movie.
    if catalog['resident']['classes'] != ['org.flashNight.neur.Server.SaveManager']:
        raise ValueError('The original RSL must retain the save namespace authority')
    sources = class_sources
    if sources is None:
        class_root = root/'scripts/类定义'
        sources = {p.relative_to(class_root).as_posix():p.read_bytes()
                   for p in sorted(class_root.rglob('*.as'))}
    for fqn in owners:
        if fqn.replace('.', '/')+'.as' not in sources:
            raise ValueError('Missing owned class: '+fqn)
    save_source = sources['org/flashNight/neur/Server/SaveManager.as'].decode('utf-8-sig')
    if re.search(r'\bclass\s+\S+\s+extends\b', save_source):
        raise ValueError('Resident save authority must not depend on a later parent')
    inputs = {'tools/asloader-modules.json':digest(catalog_raw)}
    outputs = {}
    for rel, data in sources.items():
        inputs['scripts/类定义/'+rel] = digest(data)
    for name in ORDER:
        for rel, data in sources.items():
            fqn = rel[:-3].replace('/', '.')
            if fqn in owners and owners[fqn] != name:
                data = projected_declaration(data, fqn, catalog[owners[fqn]]['swf'])
            outputs['tmp/asloader-modules/'+name+'/types/'+rel] = data
        refs = ['// Generated module roots; edit tools/asloader-modules.json.',
                'this._lockroot = false;', 'this.stop();']
        for fqn in catalog[name]['classes']:
            source = sources[fqn.replace('.', '/')+'.as'].decode('utf-8-sig')
            if not re.search(r'\binterface\s+'+re.escape(fqn)+r'\b', source):
                refs.append(fqn+';')
        outputs[projects[name]['roots']] = as_bytes('\n'.join(refs)+'\n')
        excluded = [fqn for fqn in owners if owners[fqn] != name]
        outputs[projects[name]['exclude']] = (
            '<excludeAssets>\n'+''.join('  <asset name="'+fqn+'"/>\n' for fqn in excluded)
            +'</excludeAssets>\n').encode('utf-8')
    origin = root/'scripts/asLoader'
    def template(rel):
        data = (root/rel).read_bytes() if template_bytes is None else template_bytes[rel]
        return data.decode('utf-8').replace('\r\n','\n').replace('\r','\n')
    settings = template('scripts/asLoader/PublishSettings.xml')
    # Normalize only this generator's fields, preserving the author's settings.
    settings = settings.replace('asLoaderLogic', 'asLoader')
    settings = re.sub(r'<PackagePaths>[^<]*</PackagePaths>', '<PackagePaths>类定义;</PackagePaths>', settings)
    document = template('scripts/asLoader/DOMDocument.xml')
    document = re.sub(r'\s*<publishHistory>[\s\S]*?</publishHistory>', '', document)
    symbols = re.search(r'\s*<symbols>[\s\S]*?</symbols>', document)
    frame = re.search(r'<DOMFrame\b[^>]*>[\s\S]*?</DOMFrame>', document)
    if not symbols or not frame or len(re.findall(r'<DOMFrame\b', document)) != 1:
        raise ValueError('Loader root must remain one owned frame')
    for name in ORDER:
        row = catalog[name]
        stem = Path(row['swf']).stem
        profile = settings.replace('asLoader.', stem+'.')
        profile = profile.replace('<flashDefaultName>1</flashDefaultName>', '<flashDefaultName>0</flashDefaultName>')
        profile = profile.replace('<defaultNames>1</defaultNames>', '<defaultNames>0</defaultNames>')
        profile = profile.replace('<PackagePaths>类定义;</PackagePaths>',
            '<PackagePaths>../tmp/asloader-modules/'+name+'/types;类定义;</PackagePaths>')
        outputs[projects[name]['profile']] = profile.encode('utf-8')
        if name != 'boot':
            outputs[projects[name]['xfl']] = (origin/'asLoader.xfl').read_bytes()
            outputs[projects[name]['mobile']] = (origin/'MobileSettings.xml').read_bytes()
        if name == 'resident':
            imports = '<symbols><Include href="asLoader.xml" itemID="65982cdb-00001469"/></symbols>'
            root_frame = '<DOMFrame index="0" keyMode="9728"><elements/></DOMFrame>'
            outputs[projects[name]['symbol']] = (
                '<DOMSymbolItem xmlns="'+NS+'" name="asLoader" linkageExportForAS="true" linkageIdentifier="asLoader">'
                '<timeline><DOMTimeline name="asLoader"><layers><DOMLayer name="bootstrap"><frames>'
                '<DOMFrame index="0" keyMode="9728"><Actionscript><script><![CDATA['
                '#include "../asLoaderModuleRoots/resident.as"\n#include "../asLoaderBootstrap.as"'
                ']]></script></Actionscript><elements/></DOMFrame></frames></DOMLayer></layers>'
                '</DOMTimeline></timeline></DOMSymbolItem>\n').encode('utf-8')
        else:
            imports = '<symbols><Include href="asLoader.xml" itemID="65982cdb-00001469"/></symbols>' if name == 'boot' else '<symbols/>'
            elements = ('<elements><DOMSymbolInstance libraryItemName="asLoader" name="_definitions" symbolType="movie clip">'
                '<matrix><Matrix/></matrix><transformationPoint><Point/></transformationPoint>'
                '</DOMSymbolInstance></elements>') if name == 'boot' else '<elements/>'
            root_frame = ('<DOMFrame index="0" keyMode="9728"><Actionscript><script><![CDATA['
                '#include "../asLoaderModuleRoots/'+name+'.as"'
                ']]></script></Actionscript>'+elements+'</DOMFrame>')
        doc = document[:frame.start()]+root_frame+document[frame.end():]
        doc = re.sub(r'\s*<symbols>[\s\S]*?</symbols>', '\n     '+imports, doc, count=1)
        # Later invocations normalize a prior generated self-closing symbols node.
        if name == 'shared' and '<symbols/>' not in doc:
            raise ValueError('Shared document symbol normalization failed')
        outputs[projects[name]['document']] = doc.encode('utf-8')
    for rel in ['tools/asloader_module_api.py','tools/build-asloader-modules.py',
                'tools/assemble-collapsed-frame.js','tools/asloader-definition-frames.js',
                'tools/swf-metadata.js','tools/asloader-module-catalog.js',
                'tools/audit-as2-class-embedding.js','tools/check-as2-inheritance-order.js',
                'scripts/compile_test.ps1','scripts/publish-asloader-modules.ps1',
                'scripts/asLoaderBootstrap.as','data/rewards/choice-rewards.runtime.json',
                'scripts/asLoader/LIBRARY/asLoader.xml',
                'scripts/asLoader/MobileSettings.xml','scripts/asLoader/asLoader.xfl']:
        inputs[rel] = digest((root/rel).read_bytes())
    # Bind the actual transitive includes, not just the frame files containing
    # their names. Business scripts can change without changing a frame include.
    inputs.update(include_fingerprints(root,
        [*sorted((root/'scripts/asLoaderManifest').glob('*.as')),root/'scripts/asLoaderBootstrap.as'],
        root/Path(catalog['boot']['xfl']).parent))
    manifest = {'schema':'cf7-asloader-module-inputs.v1',
                'owners':{name:len(catalog[name]['classes']) for name in ORDER},
                'inputs':inputs,'outputs':{rel:digest(data) for rel,data in outputs.items()}}
    outputs['tmp/asloader-modules/manifest.json'] = (json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    return outputs, manifest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--check-projects',action='store_true',
                        help='Check only the generator-owned project files under scripts/')
    args=parser.parse_args()
    outputs, manifest = plan()
    if args.check_projects:
        outputs = {p: data for p, data in outputs.items() if p.startswith('scripts/')}
    stale = [rel for rel,data in outputs.items() if not (ROOT/rel).is_file() or (ROOT/rel).read_bytes()!=data]
    if args.check or args.check_projects:
        if stale:
            print('Stale module outputs: '+', '.join(stale[:15]),file=sys.stderr);return 1
    else:
        for rel in stale:
            target = ROOT/rel; target.parent.mkdir(parents=True,exist_ok=True)
            # Write fresh bytes when switching an intrinsic/implementation. copy2
            # can backdate sources behind a CS6 ASO and silently reuse the wrong kind.
            target.write_bytes(outputs[rel])
    print(json.dumps({'ok':True,'check':args.check or args.check_projects,'updated':len(stale),'classes':manifest['owners'],'sourceFiles':len(manifest['inputs'])}))
    return 0

if __name__=='__main__':
    sys.exit(main())
