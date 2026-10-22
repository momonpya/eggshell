import json
import unittest
from citation_bridge import parse_citations, numbered_reads, locate, decode_layout


class CitationBridgeTests(unittest.TestCase):
    def test_display_range_and_producer_rank_are_preserved(self):
        text = '根拠です。[file.cc:41–45](/workspace/src/file.cc:41)'
        citations, issues = parse_citations('interpretation', 2, text, ['src/file.cc'])
        self.assertEqual(issues, ())
        self.assertEqual(len(citations), 1)
        c = citations[0]
        self.assertEqual((c.parent, c.priority, c.first, c.last), ('interpretation', 2, 41, 45))
        self.assertEqual(text[c.claim_first:c.claim_last], text)

    def test_destination_range_and_disambiguated_unicode_path(self):
        text = '[原文](https://example.invalid/blob/main/a/%E6%97%A5%E6%9C%AC.cc#L9-L11)'
        citations, issues = parse_citations('p', 0, text, ['a/日本.cc', 'b/日本.cc'])
        self.assertEqual(issues, ())
        self.assertEqual((citations[0].relative, citations[0].first, citations[0].last), ('a/日本.cc', 9, 11))

    def test_conflicting_links_unknown_paths_and_reversed_ranges_are_explicit(self):
        text = '[f:3-9](src/f:4) [f:5-3](src/f:5) [f:1](other/f:1)'
        citations, issues = parse_citations('p', 0, text, ['src/f'])
        self.assertEqual(citations, ())
        self.assertEqual([x[1] for x in issues], ['conflicting-display-and-destination', 'invalid-line-interval', 'unrecorded-or-ambiguous-destination'])
        with self.assertRaises(ValueError):
            parse_citations('p', 0, text, ['../f'])

    def test_original_json_coordinates_with_banner_and_surrogate_pair(self):
        observed = 'warning: runtime banner\n    41\t条件😀\n    42\t結果\n'
        work = 'Bash\n' + json.dumps({'command': "nl -ba src/f | sed -n '41,42p'"})
        reads, reason = numbered_reads(work, ['src/f'])
        self.assertIsNone(reason)
        citation = parse_citations('p', 4, '[f:41-42](src/f:41)', ['src/f'])[0][0]
        for ascii_only in [False, True]:
            raw = json.dumps(observed, ensure_ascii=ascii_only)
            text, offsets = decode_layout(raw)
            self.assertEqual(text, observed)
            for i in range(len(text)):
                self.assertEqual(json.loads('"' + raw[offsets[i]:offsets[i + 1]] + '"'), text[i])
            matches = locate(raw, reads, [citation])
            self.assertEqual(len(matches), 1)
            self.assertTrue(matches[0].complete)
            for number, first, last in matches[0].rows:
                self.assertIn(str(number) + '\t', json.loads('"' + raw[first:last] + '"'))

    def test_multifile_line_number_ambiguity_does_not_assign_a_file(self):
        work = 'Bash\n' + json.dumps({'command': "nl -ba a/f | sed -n '1,2p'; nl -ba b/f | sed -n '1,2p'"})
        reads, reason = numbered_reads(work, ['a/f', 'b/f'])
        self.assertIsNone(reason)
        citations, _ = parse_citations('p', 0, '[f:1-2](a/f:1)', ['a/f', 'b/f'])
        self.assertEqual(locate(json.dumps('  1\tleft\n  2\tright\n'), reads, citations), ())

    def test_truncation_and_huge_target_do_not_manufacture_complete_ranges(self):
        work = 'Bash\n' + json.dumps({'command': "nl -ba src/f | sed -n '1,20p'"})
        reads, _ = numbered_reads(work, ['src/f'])
        c = parse_citations('p', 0, '[f:1-999999999999999999](src/f:1)', ['src/f'])[0]
        matches = locate(json.dumps('  1\tone\n...truncated...\n  3\tthree\n'), reads, c)
        self.assertEqual(len(matches), 2)
        self.assertTrue(all(not x.complete for x in matches))

    def test_unnumbered_and_nonliteral_commands_do_not_guess_output_offsets(self):
        for command in ["sed -n '1,2p' src/f", "nl -ba $ROOT/src/f | sed -n '1,2p'", "echo banner; nl -ba src/f | sed -n '1,2p'"]:
            reads, reason = numbered_reads('Bash\n' + json.dumps({'command': command}), ['src/f'])
            self.assertEqual(reads, ())
            self.assertIsNotNone(reason)
        self.assertEqual(numbered_reads('Bash\n[]', ['src/f']), ((), 'no-literal-command'))


if __name__ == '__main__':
    unittest.main()
