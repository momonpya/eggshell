import json
from pathlib import Path
import tempfile
import unittest
from build_synapses import read_rpc
from synapse_feedback import presented


class FeedbackAdapterTests(unittest.TestCase):
    def fixture(self):
        text='10\tif (条件) {\n11\t  return 🧪;\n'
        raw=json.dumps(text,ensure_ascii=False)
        document=dict(owner='original-owner',native=True,source=raw,
            work='Bash\n'+json.dumps(dict(command="nl -ba src/a.cpp | sed -n '10,11p'")),
            records=[dict(complete=True,uris=[],files=[dict(relative='src/a.cpp',
                content=dict(root='a'*64,bytes=999))])])
        body='\nWORK GRAPH original-owner\n  GROUNDED OUTCOME\n'+\
             f'  ORIGINAL CHARS [1,{len(raw)-1})\n  DECODED JSON STRING DATA\n'+text+'\n  TRACE\n'
        return document,text,raw,body

    def test_verified_encoded_coordinates_keep_unicode_source_lines(self):
        document,_,_,body=self.fixture()
        ranges,unknown,issues=presented(body,[document])
        self.assertFalse(issues)
        self.assertFalse(unknown)
        self.assertEqual([(r.first,r.last) for r in ranges],[(10,11)])

    def test_changed_presentation_is_unknown_instead_of_a_missing_label(self):
        document,_,_,body=self.fixture()
        ranges,unknown,issues=presented(body.replace('return','invented'),[document])
        self.assertFalse(ranges)
        self.assertIn(('src/a.cpp','a'*64,999),unknown)
        self.assertTrue(issues)

    def test_tool_ids_are_scoped_by_session_and_turn(self):
        messages=[]
        for turn in ['first-turn','second-turn']:
            for phase in ['started','completed']:
                item=dict(type='commandExecution',id='same-tool-id',command='sed a.cpp',
                          aggregatedOutput='observed' if phase=='completed' else None)
                messages.append(dict(direction='server',message=dict(method='item/'+phase,
                    params=dict(threadId='session',turnId=turn,item=item))))
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'rpc.jsonl'
            path.write_text(''.join(json.dumps(m)+'\n' for m in messages))
            calls,events=read_rpc(path)
        self.assertEqual(set(calls),{'session/first-turn/same-tool-id','session/second-turn/same-tool-id'})
        self.assertEqual(len(events),4)


if __name__=='__main__':unittest.main()
