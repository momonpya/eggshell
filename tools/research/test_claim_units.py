from dataclasses import asdict
import unittest
from citation_bridge import parse_citations
from claim_units import extract


class ClaimUnitTests(unittest.TestCase):
    def test_statements_share_only_their_own_original_dependencies(self):
        text='# 調査\n\n### 分岐\n\n- 条件を確認。[f:2-3](src/f:2)、[f:7](src/f:7)\n- 別の結果。[f:9](src/f:9)\n'
        citations,_=parse_citations('p',2,text,['src/f'])
        claims=extract('p',2,text,citations)
        self.assertEqual(len(claims),2)
        self.assertEqual(len(claims[0].citations),2)
        self.assertEqual(len(claims[1].citations),1)
        self.assertIn('条件を確認',claims[0].text)
        self.assertNotIn('別の結果',claims[0].text)
        self.assertNotIn('src/f',claims[0].text)
        for claim in claims:
            self.assertEqual(text[claim.first:claim.last].count('['),len(claim.citations))
            self.assertTrue(all(0<=a<b<=len(text) for a,b in claim.fragments))

    def test_link_only_line_uses_nearest_original_paragraph(self):
        text='過去の無関係な結論\n\n### 選択\n\n| 条件 | 結果 |\n| X | Y |\n\n[f:4-8](src/f:4)\n'
        citations,_=parse_citations('p',0,text,['src/f'])
        claim=extract('p',0,text,citations)[0]
        self.assertIn('| X | Y |',claim.text)
        self.assertIn('### 選択',claim.text)
        self.assertNotIn('無関係',claim.text)

    def test_fenced_headings_do_not_change_the_context(self):
        text='# 実際\n\n```text\n# データ\n```\n\n根拠。[f:1](src/f:1)'
        citations,_=parse_citations('p',0,text,['src/f'])
        claim=extract('p',0,text,citations)[0]
        self.assertIn('# 実際',claim.text)
        self.assertNotIn('# データ',claim.text)

    def test_producer_mismatch_is_rejected(self):
        text='根拠。[f:1](src/f:1)'
        citations,_=parse_citations('p',0,text,['src/f'])
        with self.assertRaises(ValueError):
            extract('other',0,text,citations)


if __name__=='__main__':
    unittest.main()
