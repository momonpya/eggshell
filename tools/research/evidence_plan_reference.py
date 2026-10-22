"""Research-only bounded global selection; never imported by the Eggshell runtime.

Supports are query-side relevance hints, not facts or completion authority.
A bundle contributes support only with its whole declared dependency closure.
Scores saturate per query facet; source length never enters the value function.
The source adapter and relevance calibration are deliberately outside this core.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Atom:
    key: str
    cost: tuple[int, int]


@dataclass(frozen=True)
class Bundle:
    key: str
    requires: tuple[str, ...]
    supports: tuple[tuple[str, int], ...]


@dataclass(frozen=True)
class Plan:
    selected: tuple[str, ...]
    paid: tuple[str, ...]
    cost: tuple[int, int]
    support: tuple[tuple[str, int], ...]
    lower: tuple[int, ...]
    upper: tuple[int, ...]
    expanded: int
    exhausted: bool


def select(atoms, bundles, facets, fixed, limit, steps):
    """Lexicographic max-min support, then cost and canonical key tie breaks.

    Exact on an exhausted search. At a work cutoff, return a feasible incumbent
    and an optimistic objective bound. Bounds concern this declared surrogate,
    never answer correctness, recall, or model-token savings. The expansion
    quota is deterministic; the caller must separately enforce a wall deadline.
    """
    atoms = tuple(sorted(atoms, key=lambda a: a.key))
    bundles = tuple(sorted(bundles, key=lambda b: b.key))
    facets = tuple(sorted(facets))
    if len({a.key for a in atoms}) != len(atoms):
        raise ValueError("duplicate atom key")
    if len({b.key for b in bundles}) != len(bundles):
        raise ValueError("duplicate bundle key")
    if len(set(facets)) != len(facets):
        raise ValueError("duplicate query facet")
    if steps < 0 or any(v < 0 for v in (*fixed, *limit)):
        raise ValueError("negative limit or search quota")
    if any(fixed[k] > limit[k] for k in (0, 1)):
        raise ValueError("fixed packet does not fit")
    if any(v < 0 for a in atoms for v in a.cost):
        raise ValueError("negative atom cost")
    atom_index = {a.key: i for i, a in enumerate(atoms)}
    facet_index = {f: i for i, f in enumerate(facets)}
    masks, supports = [], []
    for bundle in bundles:
        if not bundle.requires or len(set(bundle.requires)) != len(bundle.requires):
            raise ValueError("empty or duplicate dependency closure")
        if len({f for f, _ in bundle.supports}) != len(bundle.supports):
            raise ValueError("duplicate facet support")
        if any(a not in atom_index for a in bundle.requires):
            raise ValueError("undeclared prerequisite")
        if any(f not in facet_index or v < 0 for f, v in bundle.supports):
            raise ValueError("undeclared or negative facet support")
        masks.append(sum(1 << atom_index[a] for a in bundle.requires))
        row = [0] * len(facets)
        for f, v in bundle.supports:
            row[facet_index[f]] = v
        supports.append(tuple(row))

    def join(left, right):
        return tuple(max(a, b) for a, b in zip(left, right))

    def score(values):
        return tuple(sorted(values))

    def charge(mask):
        return tuple(sum(a.cost[k] for i, a in enumerate(atoms) if mask >> i & 1)
                     for k in (0, 1))

    # A union of all remaining supports ignores their costs, so it is an upper
    # bound even when prerequisites and shared costs are not additive by bundle.
    zero = (0,) * len(facets)
    suffix = [zero] * (len(bundles) + 1)
    for i in range(len(bundles) - 1, -1, -1):
        suffix[i] = join(supports[i], suffix[i + 1])
    stack = [(0, (), 0, fixed, zero)]
    best = ((), 0, fixed, zero)
    expanded = 0
    while stack and expanded < steps:
        i, selected, paid, cost, values = stack.pop()
        expanded += 1
        names = tuple(bundles[j].key for j in selected)
        best_names = tuple(bundles[j].key for j in best[0])
        rank = (cost, len(selected), names)
        best_rank = (best[2], len(best[0]), best_names)
        if score(values) > score(best[3]) or (score(values) == score(best[3]) and rank < best_rank):
            best = (selected, paid, cost, values)
        if i == len(bundles) or score(join(values, suffix[i])) < score(best[3]):
            continue
        stack.append((i + 1, selected, paid, cost, values))
        fresh = masks[i] & ~paid
        delta = charge(fresh)
        after = tuple(cost[k] + delta[k] for k in (0, 1))
        if all(after[k] <= limit[k] for k in (0, 1)):
            stack.append((i + 1, selected + (i,), paid | masks[i], after, join(values, supports[i])))
    lower = score(best[3])
    upper = max([lower] + [score(join(values, suffix[i])) for i, _, _, _, values in stack])
    return Plan(tuple(bundles[i].key for i in best[0]),
                tuple(a.key for i, a in enumerate(atoms) if best[1] >> i & 1),
                best[2], tuple(zip(facets, best[3])), lower, upper, expanded, not stack)
