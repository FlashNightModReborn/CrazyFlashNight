from pathlib import Path
import gzip, hashlib, io, json, zipfile

ROOT = Path(__file__).resolve().parents[2]
TMP = Path(__file__).resolve().parent
LIMIT = 8_000_000

def lp(path):
    value = str(Path(path).resolve())
    return Path(value if value.startswith('\\\\?\\') else '\\\\?\\' + value)

def read(path): return lp(path).read_bytes()
def digest(data): return hashlib.sha256(data).hexdigest()
def sha(path): return digest(read(path))
def js(path): return json.loads(read(path).decode('utf-8-sig'))

def put(path, data):
    path = lp(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert read(path) == data, 'Preserve existing evidence: ' + str(path)
    else:
        path.write_bytes(data)

def jput(path, data):
    put(path, (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))

class Package:
    def __init__(self, out):
        self.out = Path(out)
        self.mapping = []

    def copy(self, source, relative):
        self.bytes(read(source), relative, str(source))

    def bytes(self, original, relative, source=None):
        encoded, encoding = original, 'identity'
        if len(original) > LIMIT:
            encoded, encoding = gzip.compress(original, compresslevel=9, mtime=0), 'gzip'
            relative += '.gz'
        pieces = [encoded[i:i+LIMIT] for i in range(0, len(encoded), LIMIT)] or [b'']
        paths = []
        for index, data in enumerate(pieces):
            name = relative + ('.part%03d' % (index+1) if len(pieces) > 1 else '')
            put(self.out/name, data)
            paths.append({'path':name, 'bytes':len(data), 'sha256':digest(data)})
        restored = b''.join(read(self.out/p['path']) for p in paths)
        if encoding == 'gzip': restored = gzip.decompress(restored)
        assert restored == original
        self.mapping.append({'source':source, 'originalBytes':len(original), 'originalSha256':digest(original),
            'encoding':encoding, 'parts':paths})

    def tree(self, source, relative):
        source = lp(source)
        for file in source.rglob('*'):
            if file.is_file(): self.copy(file, (Path(relative)/file.relative_to(source)).as_posix())

    def freeze(self, paths, relative='frozen-inputs.zip'):
        paths = sorted(set(paths)); archive = io.BytesIO(); index = []
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for path in paths:
                assert not Path(path).is_absolute() and '..' not in Path(path).parts
                data = read(ROOT/path); info = zipfile.ZipInfo(path, (2026,10,17,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED
                z.writestr(info, data, compresslevel=9)
                index.append({'path':path,'bytes':len(data),'sha256':digest(data)})
        with zipfile.ZipFile(io.BytesIO(archive.getvalue())) as z:
            assert z.namelist() == paths
            for row in index: assert digest(z.read(row['path'])) == row['sha256']
        self.bytes(archive.getvalue(), relative, 'current verified source inputs')
        jput(self.out/(relative+'.index.json'), {'files':index})
        return index

    def collect(self, label, experiment, plan_path, require_qualified=False):
        source = ROOT/'tmp/arena-worker-experiments'/experiment
        report = js(source/'experiment-report.json')
        if require_qualified: assert report['qualified'] and report['status']=='completed' and not report['errors']
        self.tree(source, label+'/coordinator')
        self.tree(plan_path, label+'/plan')
        rows, identities = [], []
        for group in report['groups']:
            if require_qualified: assert group['globalSaveUnchanged'] and group['seedSourcesUnchanged']
            for outcome in group['outcomes']:
                if require_qualified:
                    assert outcome['cleanupVerified'] and outcome['protectedSavesVerified'] and outcome['runtimeResourcesVerified'] and outcome['status']=='completed'
                p = lp(outcome['expectedReceiptPath'])
                if not p.is_file(): continue
                receipt = js(p)
                if outcome.get('receiptSha256'): assert sha(p)==outcome['receiptSha256'].removeprefix('sha256:')
                if require_qualified: assert receipt['runtimeUnchanged'] and receipt['resourcesUnchanged'] and not receipt['errors']
                self.tree(p.parent, label+'/'+outcome['jobId']+'/worker-attempt')
                identities.append(receipt.get('runtimeIdentity'))
                result_path = receipt.get('resultPath')
                if result_path and lp(result_path).is_file():
                    if receipt.get('resultSha256'): assert sha(result_path)==receipt['resultSha256'].removeprefix('sha256:')
                    for line in read(result_path).decode('utf-8-sig').splitlines():
                        row = json.loads(line)
                        if require_qualified: assert not row['errors']
                        rows.append(row)
        return report, rows, identities

    def finish(self):
        jput(self.out/'lossless-mapping.json', {'files':self.mapping})
        base=lp(self.out)
        rows = [{'path':p.relative_to(base).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}
            for p in base.rglob('*') if p.is_file() and p!=base/'integrity.json']
        jput(self.out/'integrity.json', {'files':rows,'fileCount':len(rows),'totalBytes':sum(p['bytes'] for p in rows)})
        for row in rows: assert sha(self.out/row['path'])==row['sha256']
        return {'files':len(rows),'bytes':sum(p['bytes'] for p in rows)}
