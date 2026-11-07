"""Data/route regressions. Native lifecycle and real-window acceptance are separate gates."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('intro_book_builder',ROOT/'tools/build-book-definition.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class ChapterIntroTests(unittest.TestCase):
    def setUp(self):
        self.registry=json.loads(builder.INTRO_SOURCE.read_text(encoding='utf8'))
        self.campus=json.loads(builder.SOURCE.read_text(encoding='utf8'))
        self.cf6=json.loads(builder.CF6_SOURCE.read_text(encoding='utf8'))
        self.type61=json.loads(builder.TYPE61_SOURCE.read_text(encoding='utf8'))

    def test_complete_opening_matrix_and_no_extra_pages(self):
        expected=[('repair-campus',self.campus,[(0,'prologue',False),(6,'boss',False)]),
            ('cf6-sting',self.cf6,[(1,'cf6-s1',True),(2,'cf6-s2',True),(3,'cf6-s3',True),(7,'cf6-s4',True),(8,'cf6-s5',True),(18,'cf6-s6',True)]),
            ('cf6-sting',self.type61,[(1,'cf6-s1',True),(2,'cf6-s2',True),(3,'cf6-s3',True),(7,'cf6-s4',True),(8,'cf6-s5',True),(18,'cf6-s6',True)])]
        count=0
        for book,data,rows in expected:
            with self.subTest(book=book,route=data.get('routeId')):
                result=builder.apply_chapter_intros(data,self.registry)
                self.assertEqual(rows,[(p['chapter'],p['pageId'],p['bgmLease']) for p in result['chapterIntros']])
                count+=len(rows)
                for index,page,lease in rows:
                    row=next(r for r in self.registry['entries'] if r['bookId']==book and r['pageId']==page)
                    self.assertEqual(row['background'],data['maps'][index]['background'])
                    self.assertIs(lease,row['bgmLease'])
        self.assertEqual(14,count)
        self.assertEqual(8,len(self.registry['entries']))
        self.assertFalse({'cf6-s7','cf6-end','lee-ambush','lee-breakout'} & {r['pageId'] for r in self.registry['entries']})

    def test_map_reordering_resolves_authoring_identity(self):
        original=copy.deepcopy(self.campus)
        self.campus['maps'].reverse()
        result=builder.apply_chapter_intros(self.campus,self.registry)
        self.assertEqual([(0,'boss'),(6,'prologue')],[(p['chapter'],p['pageId']) for p in result['chapterIntros']])
        self.assertEqual(original['maps'],list(reversed(self.campus['maps'])))

    def test_registry_rejects_duplicate_foreign_or_malformed_entries(self):
        variants=[]
        duplicate=copy.deepcopy(self.registry);duplicate['entries'].append(duplicate['entries'][0]);variants.append(duplicate)
        for key,value in [('bookId','foreign-book'),('pageId','cf6-s1'),('pageId','unknown-page'),('bgmLease',1),('background','missing.swf')]:
            item=copy.deepcopy(self.registry);item['entries'][0][key]=value;variants.append(item)
        extra=copy.deepcopy(self.registry);extra['entries'][0]['chapter']=0;variants.append(extra)
        for registry in variants:
            with self.subTest(registry=registry):
                with self.assertRaises(ValueError):builder.apply_chapter_intros(self.campus,registry)

    def test_background_must_identify_one_map(self):
        self.campus['maps'].append(copy.deepcopy(self.campus['maps'][0]))
        with self.assertRaises(ValueError):builder.apply_chapter_intros(self.campus,self.registry)

    def test_authoring_input_is_not_mutated_and_projection_is_owned(self):
        snapshot=copy.deepcopy(self.cf6)
        result=builder.apply_chapter_intros(self.cf6,self.registry)
        self.assertEqual(snapshot,self.cf6)
        result['maps'][0]['id']='changed'
        self.assertEqual(snapshot,self.cf6)

if __name__=='__main__':unittest.main(verbosity=2)
