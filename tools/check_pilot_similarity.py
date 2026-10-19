#!/usr/bin/env python3
"""Reject nomination-only evidence for the experimental equality control."""
from copy import deepcopy
import unittest

from pilot_similarity_probe import promoted_generators


class SimilarityEvidenceControls(unittest.TestCase):
    def setUp(self):
        self.left, self.right = ["atom", [1]], ["atom", [2]]
        self.rows = [dict(kind="experimental-similarity-identity-nomination", matches=[dict(
            incomingFragmentIdentity=False, currentFragment=self.left, pastFragment=self.right)])]
        self.selection = dict(runLocal=[dict(scope="run", left=self.left, right=self.right)])

    def test_actual_generator_is_required(self):
        self.assertEqual(promoted_generators(self.rows, self.selection), 1)
        with self.assertRaisesRegex(ValueError, "actual"):
            promoted_generators(self.rows, dict(runLocal=[]))

    def test_unrelated_or_persistent_edges_cannot_substitute(self):
        for change in [dict(scope="persistent"), dict(right=["atom", [3]])]:
            edge = dict(self.selection["runLocal"][0], **change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                promoted_generators(self.rows, dict(runLocal=[edge]))

    def test_existing_identity_is_not_a_new_experimental_generator(self):
        rows = deepcopy(self.rows)
        rows[0]["matches"][0]["incomingFragmentIdentity"] = True
        with self.assertRaisesRegex(ValueError, "No new"):
            promoted_generators(rows, self.selection)

    def test_symmetric_pair_and_duplicate_records_count_once(self):
        reversed_edge = dict(scope="run", left=self.right, right=self.left)
        self.assertEqual(promoted_generators(self.rows * 2, dict(runLocal=[reversed_edge])), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
