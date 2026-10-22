"""Original citation-bearing statements as advisory retrieval labels.

Each encoder view is a deterministic projection of saved prose and its original
headings. Citations remain typed dependencies. No URL, source file, answer oracle,
or generative model is consulted, and this module grants no completion authority.
"""
from dataclasses import asdict,dataclass
import hashlib
import re


LINK = re.compile(r'(?<!!)\[([^\]\n]*)\]\(([^)\n]+)\)')


@dataclass(frozen=True)
class Claim:
    parent: str
    parent_priority: int
    first: int
    last: int
    fragments: tuple[tuple[int,int], ...]
    text: str
    text_sha256: str
    citations: tuple[dict, ...]


def original_headings(text, stop):
    stack,offset,fence = [],0,None
    for line in text.splitlines(keepends=True):
        if offset>=stop:
            break
        stripped=line.lstrip()
        marker=re.match(r'(`{3,}|~{3,})',stripped)
        if marker:
            if fence is None:
                fence=(marker[1][0],len(marker[1]))
            elif marker[1][0]==fence[0] and len(marker[1])>=fence[1]:
                fence=None
        elif fence is None:
            heading=re.match(r'^ {0,3}(#{1,6})\s+\S',line)
            if heading:
                depth=len(heading[1])
                stack=[h for h in stack if h[0]<depth]+[(depth,offset,offset+len(line.rstrip('\r\n')))]
        offset+=len(line)
    return [(a,b) for _,a,b in stack]


def clean_links(text):
    # Paths/line numbers are carried in dependency records, not invented prose.
    return LINK.sub('',text).strip()


def extract(parent,priority,text,citations):
    links=list(LINK.finditer(text))
    grouped={}
    for citation in citations:
        c=asdict(citation) if not isinstance(citation,dict) else dict(citation)
        if c['parent']!=parent or c['priority']!=priority or not 0<=c['ordinal']<len(links):
            raise ValueError('citation does not belong to this original producer')
        link=links[c['ordinal']]
        first=text.rfind('\n',0,link.start())+1
        stop=text.find('\n',link.end())
        last=len(text) if stop==-1 else stop
        grouped.setdefault((first,last),[]).append(c)
    result=[]
    for (first,last),dependencies in sorted(grouped.items()):
        body=clean_links(text[first:last])
        fragments=[]
        if not any(c.isalnum() for c in body):
            # A standalone citation line labels the preceding original
            # paragraph/table; it does not label the whole historical answer.
            end=first
            while end>0 and text[end-1] in '\r\n \t':
                end-=1
            a=text.rfind('\n\n',0,end)+2
            if a==1:
                a=0
            if a<end:
                fragments.append((a,end))
        fragments.append((first,last))
        headings=original_headings(text,fragments[0][0])
        fragments=tuple(dict.fromkeys(headings+fragments))
        view='\n'.join(clean_links(text[a:b]) for a,b in fragments if clean_links(text[a:b]))
        if not any(c.isalnum() for c in view):
            continue
        result.append(Claim(parent,priority,first,last,fragments,view,
                            hashlib.sha256(view.encode()).hexdigest(),tuple(dependencies)))
    return tuple(result)
