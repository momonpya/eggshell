from fractions import Fraction
import copy
import itertools
import unittest
from signal_coverage import assess, select


class SignalCoverageTests(unittest.TestCase):
    def fixture(self):
        return dict(nodeCosts=[[4,4],[3,6],[3,6],[9,9]],
                    features=[dict(weights=[8,0]),dict(weights=[0,8]),dict(weights=[10,0])],
                    offers=[dict(closure=[0,1],covers=[0]),dict(closure=[0,2],covers=[1]),dict(closure=[3],covers=[2])],
                    unitKeys=['branch','effect','prose'],totals=[18,8],fixed=[0,0],limit=[10,16],chosen=[2])

    def test_balanced_shared_dependencies(self):
        p = self.fixture()
        result = select(p,1000)
        self.assertEqual(set(result['selected']),{0,1})
        self.assertEqual(result['cost'],[10,16])
        self.assertEqual(result['score'],['4/9','1'])

    def test_quotas_and_budgets_preserve_feasibility_and_seed(self):
        for chars in range(13):
            for byte_limit in range(19):
                p = self.fixture()
                p.update(limit=[chars,byte_limit],chosen=[])
                feasible=[]
                for bits in itertools.product((0,1),repeat=3):
                    selected=[i for i,b in enumerate(bits) if b]
                    checked=assess(p,selected)
                    if checked['feasible']:
                        feasible.append((checked['score'],selected))
                optimum=max(s for s,_ in feasible)
                p['chosen']=feasible[-1][1]
                for quota in [0,2,3,10,1000]:
                    with self.subTest(chars=chars,bytes=byte_limit,quota=quota):
                        result=select(p,quota)
                        checked=assess(p,result['selected'])
                        self.assertTrue(checked['feasible'])
                        self.assertEqual(list(checked['cost']),result['cost'])
                        self.assertEqual([str(x) for x in checked['score']],result['score'])
                        self.assertGreaterEqual(checked['score'],assess(p,p['chosen'])['score'])
                        self.assertLessEqual(checked['score'],optimum)
                        self.assertLessEqual(result['proposalCount'],quota)

    def test_input_order_and_identical_bundle_copy(self):
        p=self.fixture()
        expected=select(p,1000)
        for order in itertools.permutations(range(3)):
            q=copy.deepcopy(p)
            q['offers']=[p['offers'][i] for i in order]
            q['unitKeys']=[p['unitKeys'][i] for i in order]
            q['chosen']=[order.index(i) for i in p['chosen']]
            actual=select(q,1000)
            self.assertEqual({q['unitKeys'][i] for i in actual['selected']},{p['unitKeys'][i] for i in expected['selected']})
            self.assertEqual((actual['cost'],actual['score']),(expected['cost'],expected['score']))
        p['offers'].append(copy.deepcopy(p['offers'][0]))
        p['unitKeys'].append('duplicate')
        actual=select(p,1000)
        self.assertEqual((actual['cost'],actual['score']),(expected['cost'],expected['score']))
        self.assertEqual(actual['activeOffers'],3)

    def test_absent_reference_channel(self):
        p=self.fixture()
        for f in p['features']:
            f['weights'][1]=0
        p['totals'][1]=0
        result=select(p,1000)
        self.assertEqual(len(result['score']),1)
        self.assertTrue(assess(p,result['selected'])['feasible'])


if __name__=='__main__':
    unittest.main()
