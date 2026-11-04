import Eggshell.LexicalEvidence

open Eggshell Eggshell.LexicalEvidence

-- Every positive original window is retained; no result-count cutoff is used.
#guard positions (SearchRank.terms "tail_key") ["front", "tail_key"] == [1]
#guard positions [] ["front", "tail_key"] == []
#guard positions ["missing"] ["front", "tail_key"] == []
#guard positions ((SearchRank.terms "tail_key") ++ (SearchRank.terms "tail_key")) ["tail_key"] == [0]
#guard positions (SearchRank.terms "tail_key") ["tail_key", "tail_key", "tail_key"] == [0,1,2]
#guard positions (SearchRank.terms "日本語") ["unrelated", "日本語"] == [1]
#guard positions (SearchRank.terms "커널") ["unrelated", "커널"] == [1]
#guard positions (SearchRank.terms "вектор") ["unrelated", "вектор"] == [1]
#guard positions (SearchRank.terms "café") ["unrelated", "café"] == [1]

#print axioms Eggshell.LexicalEvidence.positions_exact
