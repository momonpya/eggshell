"""Independent small exhaustive checks for a research selector, not integration tests."""
import itertools
import unittest
from evidence_plan_reference import Atom, Bundle, select


def exhaustive(atoms, bundles, facets, fixed, limit):
    costs = {a.key: a.cost for a in atoms}
    best = None
    for bits in itertools.product((0, 1), repeat=len(bundles)):
        chosen = [b for b, bit in zip(bundles, bits) if bit]
        paid = set(a for b in chosen for a in b.requires)
        cost = tuple(fixed[k] + sum(costs[a][k] for a in paid) for k in (0, 1))
        if any(cost[k] > limit[k] for k in (0, 1)):
            continue
        values = [max([0] + [v for b in chosen for f, v in b.supports if f == facet])
                  for facet in facets]
        candidate = (tuple(sorted(values)), cost, tuple(sorted(b.key for b in chosen)))
        if best is None or candidate[0] > best[0] or (candidate[0] == best[0] and
                (candidate[1], len(candidate[2]), candidate[2]) < (best[1], len(best[2]), best[2])):
            best = candidate
    return best


class EvidencePlannerTests(unittest.TestCase):
    def setUp(self):
        self.atoms = [Atom('provenance', (4, 4)), Atom('condition', (3, 6)),
                      Atom('result', (3, 6)), Atom('long-prose', (9, 9))]
        self.bundles = [Bundle('explanation', ('long-prose',), (('why', 10),)),
                        Bundle('branch', ('provenance', 'condition'), (('why', 8),)),
                        Bundle('effect', ('provenance', 'result'), (('what', 8),))]

    def test_global_shared_closure_and_both_facets(self):
        p = select(self.atoms, self.bundles, ['why', 'what'], (0, 0), (10, 16), 1000)
        self.assertEqual(p.selected, ('branch', 'effect'))
        self.assertEqual(p.cost, (10, 16))
        self.assertEqual(p.lower, (8, 8))
        self.assertEqual(p.lower, p.upper)
        self.assertTrue(p.exhausted)

    def test_quotas_and_every_small_budget_against_exhaustive(self):
        for chars in range(16):
            for byte_limit in range(18):
                optimum = exhaustive(self.atoms, self.bundles, ['why', 'what'], (0, 0), (chars, byte_limit))
                for quota in [0, 1, 3, 7, 1000]:
                    with self.subTest(chars=chars, bytes=byte_limit, quota=quota):
                        p = select(self.atoms, self.bundles, ['why', 'what'], (0, 0), (chars, byte_limit), quota)
                        self.assertLessEqual(p.cost, (chars, byte_limit))
                        self.assertLessEqual(p.cost[1], byte_limit)
                        self.assertLessEqual(p.lower, optimum[0])
                        self.assertGreaterEqual(p.upper, optimum[0])
                        if p.exhausted:
                            self.assertEqual((p.lower, p.cost, p.selected), optimum)

    def test_input_order_and_duplicate_observation_do_not_add_value(self):
        original = select(self.atoms, self.bundles, ['why', 'what'], (0, 0), (10, 16), 1000)
        duplicate = Bundle('duplicate-branch', ('provenance', 'condition'), (('why', 8),))
        for order in itertools.permutations(self.bundles):
            p = select(self.atoms[::-1], order, ['what', 'why'], (0, 0), (10, 16), 1000)
            self.assertEqual(p, original)
        p = select(self.atoms, self.bundles + [duplicate], ['why', 'what'], (0, 0), (10, 16), 1000)
        self.assertEqual((p.lower, p.cost, p.selected), (original.lower, original.cost, original.selected))

    def test_partial_prerequisites_cannot_earn_support(self):
        p = select(self.atoms, self.bundles[1:2], ['why'], (0, 0), (3, 6), 100)
        self.assertEqual(p.selected, ())
        self.assertEqual(p.lower, (0,))
        self.assertEqual(p.paid, ())

    def test_unknown_dependency_rejected(self):
        with self.assertRaisesRegex(ValueError, 'undeclared prerequisite'):
            select(self.atoms, [Bundle('bad', ('missing',), (('why', 1),))], ['why'], (0, 0), (10, 10), 10)


if __name__ == '__main__':
    unittest.main()
