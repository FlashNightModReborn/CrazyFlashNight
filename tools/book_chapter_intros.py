"""Shared authoring-identity resolver for runtime data and native test fixtures."""
import copy
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
INTRO_SOURCE = ROOT / 'data/books/chapter-intros.json'

def apply_chapter_intros(data, registry=None):
    """Resolve authoring identities once; runtime consumes chapter declarations uniformly."""
    registry = json.loads(INTRO_SOURCE.read_text(encoding='utf-8')) if registry is None else registry
    if set(registry) != {'schema','entries'} or registry['schema'] != 'book-chapter-intros.v1' or type(registry['entries']) is not list or len(registry['entries']) > 32:
        raise ValueError('invalid chapter intro registry')
    catalog = {}
    for book_id, source in [('repair-campus',ROOT/'data/books/repair-campus-comic.json'),
                            ('cf6-sting',ROOT/'tools/cf6-story-migration/generated/comic-story.fragment.json')]:
        content=json.loads(source.read_text(encoding='utf-8'))
        for page in content.get('pages',content.get('segments',[])): catalog[page['id']]=book_id
    seen=set(); plans=[]
    for row in registry['entries']:
        if set(row) != {'bookId','background','pageId','bgmLease'} or any(type(row[k]) is not str or not row[k] for k in ('bookId','background','pageId')) or type(row['bgmLease']) is not bool:
            raise ValueError('invalid chapter intro entry')
        identity=(row['bookId'],row['background'])
        if identity in seen or catalog.get(row['pageId']) != row['bookId']:
            raise ValueError('duplicate or foreign chapter intro')
        seen.add(identity)
        if row['bookId'] != data['id']: continue
        matches=[i for i,m in enumerate(data['maps']) if m['background']==row['background']]
        if len(matches) != 1: raise ValueError('chapter intro background must resolve exactly once: '+row['background'])
        plans.append(dict(chapter=matches[0],pageId=row['pageId'],bgmLease=row['bgmLease']))
    result=copy.deepcopy(data)
    result['chapterIntros']=sorted(plans,key=lambda p:p['chapter'])
    return result
