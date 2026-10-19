#!/usr/bin/env python3
"""Generate compact Unicode character categories, not a language dictionary."""
import argparse
import hashlib
from pathlib import Path
import unicodedata


def ranges(kinds):
    rows = []
    start = None
    for scalar in range(0x110001):
        included = scalar < 0x110000 and unicodedata.category(chr(scalar))[0] in kinds
        if included and start is None:
            start = scalar
        elif not included and start is not None:
            rows.append((start, scalar-1))
            start = None
    return rows


def render():
    if unicodedata.unidata_version != "16.0.0":
        raise ValueError("Use the same Unicode data as Eggshell.SearchUnicode")
    result = ['module', '', 'public import Std', '', '@[expose] public section', '',
              'namespace Eggshell.RetrievalResearch.Unicode', '',
              '/-- Generated Unicode categories. No words, analyzer or runtime dependency. -/']
    for name, kinds in [('lettersNumbers', 'LN'), ('marks', 'M')]:
        rows = ranges(kinds)
        result.append(f'def {name} : Array (Nat × Nat) := #[')
        for offset in range(0, len(rows), 6):
            result.append('  ' + ', '.join(f'({a}, {b})' for a,b in rows[offset:offset+6]) +
                          (',' if offset+6 < len(rows) else ''))
        result.extend([']', ''])
    width = [(n, unicodedata.normalize('NFKC', chr(n))) for n in range(0xff61,0xffa0)]
    compositions = []
    for base in range(0x3040,0x3100):
        for mark in [0x3099,0x309a]:
            composed = unicodedata.normalize('NFC', chr(base)+chr(mark))
            if len(composed)==1:
                compositions.append((base,mark,ord(composed)))
    result.append('def kanaWidth : Std.HashMap Nat String := Std.HashMap.ofList [')
    import json
    for offset in range(0,len(width),6):
        result.append('  '+', '.join(f'({n}, {json.dumps(s,ensure_ascii=False)})' for n,s in width[offset:offset+6])+
                      (',' if offset+6<len(width) else ''))
    result.extend([']','', 'def kanaCompositions : Std.HashMap (Nat × Nat) Nat := Std.HashMap.ofList ['])
    for offset in range(0,len(compositions),6):
        result.append('  '+', '.join(f'(({a}, {b}), {c})' for a,b,c in compositions[offset:offset+6])+
                      (',' if offset+6<len(compositions) else ''))
    result.extend([']','', 'def contains (ranges : Array (Nat × Nat)) (c : Char) : Bool :=',
        '  (ranges.binSearch (c.toNat, c.toNat) (fun left right => left.2 < right.1)).isSome', '',
        'def letterNumber (c : Char) : Bool := contains lettersNumbers c',
        'def mark (c : Char) : Bool := contains marks c', '',
        '/-- Width equivalence for ASCII and Kana only; not general NFKC or accent removal. -/',
        'def widthFold (text : String) : String := Id.run do',
        '  let mut result : Array Char := #[]',
        '  for c in text do',
        '    let folded := if 0xff01 ≤ c.toNat && c.toNat ≤ 0xff5e then',
        '      String.singleton (Char.ofNat (c.toNat - 0xfee0))',
        '      else if c.toNat == 0x3000 then " "',
        '      else (kanaWidth[c.toNat]?).getD (String.singleton c)',
        '    for next in folded do',
        '      if !result.isEmpty then',
        '        if let some combined := kanaCompositions[(result[result.size - 1]!.toNat, next.toNat)]? then',
        '          result := result.set! (result.size - 1) (Char.ofNat combined)',
        '        else result := result.push next',
        '      else result := result.push next',
        '  return String.ofList result.toList', '',
        'end Eggshell.RetrievalResearch.Unicode', ''])
    return '\n'.join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = render()
    if args.check:
        if args.output.read_text() != data:
            raise ValueError('Generated category table differs')
    else:
        if args.output.exists():
            raise FileExistsError('Refusing to overwrite a category table; use --check')
        args.output.write_text(data)
    print(hashlib.sha256(data.encode()).hexdigest())


if __name__ == '__main__':
    main()
