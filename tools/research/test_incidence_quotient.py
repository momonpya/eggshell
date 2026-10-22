import unittest
from incidence_quotient import compress


class IncidenceQuotientTests(unittest.TestCase):
    def test_joint_activation_preserves_all_four_selection_sets(self):
        original=dict(nodeCosts=[[3,7],[5,9],[11,13]],weights=[2,3,100],
                      offers=[dict(closure=[0,1],covers=[0,1]),dict(closure=[0,1,2],covers=[0,1])],
                      fixed=[2,2],limit=[12,20],chosen=[])
        quotient,mapping=compress(original)
        self.assertEqual(quotient['nodeCosts'],[[8,16],[11,13]])
        self.assertEqual(quotient['weights'],[5])
        self.assertEqual(mapping['unreachableCues'],[2])
        expected=[([],([2,2],0)),([0],([10,18],5)),([1],([21,31],5)),([0,1],([21,31],5))]
        for selected,(wanted_cost,wanted_value) in expected:
            with self.subTest(selected=selected):
                nodes={n for i in selected for n in quotient['offers'][i]['closure']}
                cues={c for i in selected for c in quotient['offers'][i]['covers']}
                cost=[2+sum(quotient['nodeCosts'][n][k] for n in nodes) for k in (0,1)]
                value=sum(quotient['weights'][c] for c in cues)
                self.assertEqual((cost,value),(wanted_cost,wanted_value))


if __name__=='__main__':
    unittest.main()
