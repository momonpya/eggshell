import unittest
from synapse_graph import SourceRange, Synapses, consume_trace, covered, key, observed_gaps


def source(first=10,last=12,fingerprint='a'*64):
    return SourceRange('src/日本語.cpp',fingerprint,1000,first,last)


class SynapseTests(unittest.TestCase):
    def test_all_three_families_and_idempotent_events(self):
        graph=Synapses();a,b=source(),source(20,21)
        aid=graph.support(a,'claim-1',{'citation':'literal'},'read-A')
        graph.support(b,'claim-2',{'citation':'literal'},'read-B')
        witness=dict(producerFinish=1,consumerStart=2,kind='path',term='src/日本語.cpp')
        graph.consume('read-A','read-B',witness);graph.consume('read-A','read-B',witness)
        graph.quote_together('answer-1',[a,b]);graph.quote_together('answer-1',[a,b])
        self.assertEqual(len(graph.consumed),1)
        self.assertEqual(len(graph.coquoted['answer-1']),2)
        self.assertEqual(set(graph.backward(['claim-2'])['ranges']),{a.identity,b.identity})
        graph.quote_together('paragraph-1',[a,b],scope='claim')
        self.assertEqual(graph.companions([aid])[b.identity],1)
        self.assertEqual(graph.companions([aid],scope='claim')[b.identity],1)
        for _ in range(2):
            self.assertEqual(graph.record_read('event',key('question'),a,[a],[],True),'omitted_then_read')
        self.assertEqual(graph.usage_counts(key('question'))[a.identity]['omitted_then_read'],1)
        self.assertTrue(graph.record_citation('citation',key('question'),b,[b]))
        self.assertEqual(graph.usage_counts(key('question'))[b.identity]['delivered_then_cited'],1)
        self.assertFalse(graph.record_citation('not-delivered',key('question'),a,[]))

    def test_reread_does_not_always_mean_missing(self):
        graph=Synapses();a=source();q=key('question')
        self.assertEqual(graph.record_read('delivered',q,a,[a],[a],True),'reread')
        self.assertEqual(graph.record_read('unknown',q,a,[a],[],False),'reread')
        self.assertEqual(graph.record_read('not-stored',q,source(13,15),[a],[],True),'reread')
        self.assertEqual(graph.record_read('changed',q,source(fingerprint='b'*64),[a],[],True),'source_changed')
        with self.assertRaises(ValueError):graph.record_read('delivered',q,a,[a],[],True)
        with self.assertRaises(ValueError):graph.record_read('plain','plaintext question',a,[a],[],True)

    def test_range_union_and_fingerprint_boundary(self):
        self.assertTrue(covered(source(1,10),[source(1,4),source(5,10)]))
        self.assertFalse(covered(source(1,10),[source(1,4),source(6,10)]))
        self.assertFalse(covered(source(),[source(fingerprint='b'*64)]))
        self.assertFalse(covered(source(1,10**30),[source(1,4)]))
        with self.assertRaises(ValueError):SourceRange('../escape','a'*64,1,1,2)

    def test_parallelism_future_outputs_and_unfinished_calls(self):
        graph=Synapses()
        events=[dict(phase='start',occurrence='a',ordinal=0,text='search'),
                dict(phase='start',occurrence='b',ordinal=1,text='src/a.cpp:10'),
                dict(phase='finish',occurrence='a',ordinal=2,text='src/a.cpp:10'),
                dict(phase='finish',occurrence='b',ordinal=3,text='done'),
                dict(phase='start',occurrence='c',ordinal=4,text='read src/a.cpp:10'),
                dict(phase='finish',occurrence='c',ordinal=5,text='done'),
                dict(phase='start',occurrence='unfinished',ordinal=6,text='src/a.cpp')]
        result=consume_trace(graph,events)
        self.assertEqual(result['unfinished'],['unfinished'])
        pairs={(x['producer'],x['consumer']) for x in graph.consumed.values()}
        self.assertEqual(pairs,{('a','c')})
        with self.assertRaises(ValueError):graph.consume('c','a',dict(producerFinish=5,consumerStart=0))

    def test_feedback_only_records_stored_undelivered_portions(self):
        gaps=observed_gaps(source(1,100),[source(1,20),source(40,60)],
                           [source(5,10),source(15,50)])
        self.assertEqual([(r.first,r.last) for r in gaps],[(1,4),(11,14),(51,60)])
        self.assertEqual(observed_gaps(source(1,10**30),[],[]),[])
        self.assertEqual(observed_gaps(source(),[source(fingerprint='b'*64)],[]),[])

    def test_no_quadratic_coquotation_clique(self):
        graph=Synapses();ranges=[source(i,i) for i in range(1,1001)]
        graph.quote_together('answer',ranges)
        graph.quote_together('answer',ranges)
        self.assertEqual(len(graph.coquoted['answer']),1000)
        self.assertEqual(sum(map(len,graph.coquoted_by.values())),1000)
        self.assertNotIn('union',graph.export())


if __name__=='__main__':unittest.main()
