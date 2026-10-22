"""Lossless advisory citation inputs for the research planner; no file IO/Union.

Only declared paths and literal numbered-read metadata are understood. A matched
line is a hint into an existing saved scalar, never a claim that a shell ran or
that a file is currently fresh. The caller supplies already admitted graph routes.
"""
from dataclasses import dataclass
import json
from pathlib import PurePosixPath
import re
import shlex
from urllib.parse import unquote


@dataclass(frozen=True)
class Citation:
    parent: str
    priority: int
    ordinal: int
    relative: str
    first: int
    last: int
    claim_first: int
    claim_last: int


@dataclass(frozen=True)
class Read:
    relative: str
    first: int
    last: int


@dataclass(frozen=True)
class Located:
    citation: Citation
    # Each half-open range refers to characters of the original saved scalar.
    rows: tuple[tuple[int, int, int], ...]
    complete: bool


def safe_relative(path):
    return bool(path) and not path.startswith('/') and '\0' not in path and all(
        p and p not in ('.', '..') for p in path.split('/'))


def parse_citations(parent, priority, text, paths):
    if priority < 0 or any(not safe_relative(p) for p in paths):
        raise ValueError('invalid rank or declared relative path')
    result, issues, seen = [], [], set()
    links = re.finditer(r'(?<!!)\[([^\]\n]*)\]\(([^)\n]+)\)', text)
    for ordinal, link in enumerate(links):
        label, url = link.groups()
        url = unquote(url.strip().removeprefix('<').removesuffix('>'))
        candidates = []
        for relative in sorted(set(paths)):
            match = re.search(r'(?:^|/)' + re.escape(relative) +
                              r'(?::|#L)(\d+)(?:[-–—]L?(\d+))?$', url)
            if match:
                candidates.append((relative, int(match[1]), int(match[2] or match[1]), bool(match[2])))
        if len(candidates) != 1:
            issues.append((ordinal, 'unrecorded-or-ambiguous-destination'))
            continue
        relative, first, last, url_range = candidates[0]
        display = re.search(re.escape(PurePosixPath(relative).name) +
                            r':(\d+)(?:[-–—](\d+))?', label)
        if display:
            a, b = int(display[1]), int(display[2] or display[1])
            if a != first or (url_range and b != last):
                issues.append((ordinal, 'conflicting-display-and-destination'))
                continue
            last = b
        if first <= 0 or last < first:
            issues.append((ordinal, 'invalid-line-interval'))
            continue
        claim_first = text.rfind('\n\n', 0, link.start()) + 2
        if claim_first == 1:
            claim_first = 0
        stop = text.find('\n\n', link.end())
        claim_last = len(text) if stop == -1 else stop
        key = (relative, first, last, claim_first, claim_last)
        if key not in seen:
            seen.add(key)
            result.append(Citation(parent, priority, ordinal, relative, first, last, claim_first, claim_last))
    return tuple(result), tuple(issues)


def decode_layout(raw):
    if not raw.startswith('"'):
        return raw, tuple(range(len(raw) + 1))
    decoded = json.loads(raw)
    if not isinstance(decoded, str):
        raise ValueError('not a saved string scalar')
    offsets, chars, i = [], [], 1
    while i < len(raw) - 1:
        first = i
        if raw[i] == '\\':
            end = i + (6 if raw[i + 1] == 'u' else 2)
            if raw[i + 1] == 'u' and 0xD800 <= int(raw[i + 2:i + 6], 16) <= 0xDBFF:
                if raw[end:end + 2] == '\\u' and 0xDC00 <= int(raw[end + 2:end + 6], 16) <= 0xDFFF:
                    end += 6
            char = json.loads('"' + raw[i:end] + '"')
        else:
            char, end = raw[i], i + 1
        if len(char) != 1:
            raise ValueError('ambiguous scalar character')
        chars.append(char)
        offsets.append(first)
        i = end
    if ''.join(chars) != decoded:
        raise ValueError('saved scalar layout disagrees with JSON decoder')
    return decoded, tuple(offsets + [len(raw) - 1])


def numbered_reads(work, paths):
    """Recognize only complete sequences of literal nl -ba PATH | sed -n RANGE.

    No positional projection of unnumbered output: banners/truncation make it
    unsafe to infer a source line from output offset. Unsupported commands are
    explicit, rather than guessed. No command is evaluated.
    """
    if any(not safe_relative(p) for p in paths):
        raise ValueError('invalid declared relative path')
    try:
        payload = json.loads(work.split('\n', 1)[1])
        if not isinstance(payload, dict):
            return (), 'no-literal-command'
        command = payload.get('command', payload.get('cmd'))
        if not isinstance(command, str):
            return (), 'no-literal-command'
        segments = []
        for line in command.splitlines():
            lexer = shlex.shlex(line, posix=True, punctuation_chars='|;&')
            lexer.whitespace_split = True
            lexer.commenters = ''
            segment = []
            for token in lexer:
                if token == ';':
                    if segment:
                        segments.append(segment)
                        segment = []
                else:
                    segment.append(token)
            if segment:
                segments.append(segment)
    except (ValueError, IndexError, TypeError):
        return (), 'invalid-literal-command'
    result = []
    for segment in segments:
        if len(segment) != 7 or segment[:2] != ['nl', '-ba'] or segment[3:6] != ['|', 'sed', '-n']:
            return (), 'unsupported-read-sequence'
        path, program = segment[2], segment[6]
        if any(c in path for c in '$`*?{}'):
            return (), 'nonliteral-read-path'
        matched = [p for p in paths if path == p or path.endswith('/' + p)]
        bounds = re.fullmatch(r'([1-9]\d*)(?:,([1-9]\d*))?p', program)
        if len(matched) != 1 or bounds is None:
            return (), 'unrecorded-or-unsupported-read'
        first, last = int(bounds[1]), int(bounds[2] or bounds[1])
        if last < first:
            return (), 'invalid-read-interval'
        result.append(Read(matched[0], first, last))
    return tuple(result), None if result else 'no-numbered-read'


def locate(raw, reads, citations):
    text, offsets = decode_layout(raw)
    rows, at = [], 0
    for line in text.splitlines(keepends=True):
        row = re.fullmatch(r' *([1-9]\d*)\t([^\n]*)(\n?)', line)
        if row:
            number = int(row[1])
            files = {r.relative for r in reads if r.first <= number <= r.last}
            if len(files) == 1:
                rows.append((next(iter(files)), number, offsets[at], offsets[at + len(line)]))
        at += len(line)
    result = []
    for citation in citations:
        groups = []
        for relative, number, first, last in rows:
            if relative != citation.relative or not citation.first <= number <= citation.last:
                continue
            if groups and groups[-1][-1][0] + 1 == number and groups[-1][-1][2] == first:
                groups[-1].append((number, first, last))
            else:
                groups.append([(number, first, last)])
        for group in groups:
            complete = group[0][0] == citation.first and group[-1][0] == citation.last and len(group) == citation.last - citation.first + 1
            result.append(Located(citation, tuple(group), complete))
    return tuple(result)
