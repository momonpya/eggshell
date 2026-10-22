import hashlib
import json
import unittest
from citation_bridge import decode_layout
from project_citations import project


class ProjectCitationTests(unittest.TestCase):
    def fixture(self):
        text = '   1\tfirst\n   2\tsecond\n'
        raw = json.dumps(text)
        _, offsets = decode_layout(raw)
        a, b, c = offsets[0], offsets[len(text.splitlines(keepends=True)[0])], offsets[-1]
        work = 'Bash\n' + json.dumps({'command': "nl -ba src/f | sed -n '1,2p'"})
        family = dict(owner='observation',workChars=len(work),sourceSha256=hashlib.sha256(raw.encode()).hexdigest(),windows=[0,1],references=[])
        context = dict(question='query',parents=[dict(owner='answer',work='parent',rank=3,text='[f:2](src/f:2)')],
                       observations=[dict(owner='observation',work='child',source=raw,
                       records=[dict(complete=True,closed=True,uris=[],files=[dict(relative='src/f',content=dict(root='0'*64,bytes=100))])])],
                       all=[dict(parent='parent',children=['child'])])
        audit = [dict(kind='EGGSHELL_CITATION_INPUT',data=context),
                 dict(kind='EGGSHELL_RANGE_SELECTION',data=dict(families=[family],units=[dict(family=0,ranges=[[a,c]]),dict(family=0,ranges=[[b,c]])])),
                 dict(kind='EGGSHELL_RANGE_UNIT',data=dict(owner='observation',position=0,ranges=[[a,c]],requested=[[a,b]])),
                 dict(kind='EGGSHELL_RANGE_UNIT',data=dict(owner='observation',position=1,ranges=[[b,c]],requested=[[b,c]]))]
        return audit,[dict(owner='observation',work=work,evidence=text)]

    def test_context_expansion_cannot_borrow_a_citations_value(self):
        audit, docs = self.fixture()
        result = project(audit, docs)
        self.assertEqual(len(result['projected']), 1)
        match = result['projected'][0]
        # Both payloads contain the cited line, but only the second payload's
        # actual search cue concerns it. The first only contains it as context.
        self.assertEqual(match['completeOffers'], [0,1])
        self.assertEqual([p['unit'] for p in match['hintOffers']], [1])
        self.assertEqual(match['citation']['priority'], 3)
        self.assertEqual(match['hintOffers'][0]['positions'][0]['queryChannelPriority'], 1)

    def test_unreached_observation_cannot_supply_citation_data(self):
        audit, docs = self.fixture()
        audit[0]['data']['all'] = []
        result = project(audit, docs)
        self.assertEqual(result['projected'], [])
        self.assertEqual(result['parents'][0]['reachableObservations'], 0)

    def test_changed_observation_inventory_is_rejected(self):
        audit, docs = self.fixture()
        docs[0]['evidence'] = 'invented observation'
        with self.assertRaisesRegex(ValueError, 'native source disagrees'):
            project(audit, docs)


if __name__ == '__main__':
    unittest.main()
