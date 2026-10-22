"""Anytime research selection over two normalized, duplicate-free signal sets.

The threshold search is a heuristic under shared costs: failure to reach a
threshold is not an infeasibility proof. Every incumbent is independently
checked, and selection never loses the seed's declared max-min objective.
No approximation factor, semantic sufficiency, or token saving is claimed.
"""
from fractions import Fraction


def assess(problem, selected):
    if len(set(selected)) != len(selected):
        raise ValueError('repeated offer')
    nodes = {n for i in selected for n in problem['offers'][i]['closure']}
    features = {c for i in selected for c in problem['offers'][i]['covers']}
    cost = tuple(problem['fixed'][k]+sum(problem['nodeCosts'][n][k] for n in nodes) for k in (0,1))
    values = tuple(sum(problem['features'][c]['weights'][k] for c in features) for k in (0,1))
    score = tuple(sorted(Fraction(values[k],problem['totals'][k]) for k in (0,1) if problem['totals'][k]))
    return dict(cost=cost,values=values,score=score,feasible=all(cost[k]<=problem['limit'][k] for k in (0,1)))


def select(problem, proposal_limit, passes=8):
    if proposal_limit < 0 or passes < 0:
        raise ValueError('negative search quota')
    totals = problem['totals']
    if totals != [sum(f['weights'][k] for f in problem['features']) for k in (0,1)]:
        raise ValueError('signal totals disagree with the declared features')
    if any(w<0 for f in problem['features'] for w in f['weights']):
        raise ValueError('negative signal weight')
    active_channels = [k for k in (0,1) if totals[k]]
    if not active_channels:
        raise ValueError('no attainable signal')
    denominator = 1
    for k in active_channels:
        denominator *= totals[k]
    multipliers = [denominator//totals[k] if totals[k] else 0 for k in (0,1)]
    scaled = [[f['weights'][k]*multipliers[k] for k in (0,1)] for f in problem['features']]
    # Identical closed offers are interchangeable for this declared problem.
    # A canonical key keeps search order independent of input enumeration.
    representatives = {}
    for i,o in enumerate(problem['offers']):
        key = (tuple(sorted(set(o['closure']))),tuple(sorted(set(o['covers']))))
        old = representatives.get(key)
        if o['covers'] and (old is None or problem['unitKeys'][i]<problem['unitKeys'][old]):
            representatives[key] = i
    order = sorted(representatives.values(),key=lambda i:problem['unitKeys'][i])
    used = 0
    trace = []
    best_selected = list(problem.get('chosen',[]))
    best = assess(problem,best_selected)
    if not best['feasible']:
        raise ValueError('infeasible seed')

    def prefer(selected):
        nonlocal best,best_selected
        candidate = assess(problem,selected)
        if not candidate['feasible']:
            raise ValueError('independent feasibility check failed')
        rank = (candidate['cost'],len(selected),tuple(sorted(problem['unitKeys'][i] for i in selected)))
        old_rank = (best['cost'],len(best_selected),tuple(sorted(problem['unitKeys'][i] for i in best_selected)))
        if candidate['score']>best['score'] or (candidate['score']==best['score'] and rank<old_rank):
            best,best_selected = candidate,list(selected)

    def fill(target):
        nonlocal used
        selected, selected_set = [], set()
        seen_nodes,seen_features = set(),set()
        cost = list(problem['fixed'])
        values = [0,0]
        cap = target.numerator*denominator
        while used+len(order)<=proposal_limit:
            choice = None
            remaining = [max(0,cap-values[k]*target.denominator) if totals[k] else 0 for k in (0,1)]
            if not any(remaining):
                break
            used += len(order)
            for i in order:
                if i in selected_set:
                    continue
                offer = problem['offers'][i]
                fresh_nodes = set(offer['closure'])-seen_nodes
                delta = tuple(sum(problem['nodeCosts'][n][k] for n in fresh_nodes) for k in (0,1))
                after = tuple(cost[k]+delta[k] for k in (0,1))
                if any(after[k]>problem['limit'][k] for k in (0,1)):
                    continue
                fresh_features = set(offer['covers'])-seen_features
                added = tuple(sum(scaled[c][k] for c in fresh_features) for k in (0,1))
                gain = sum(min(added[k]*target.denominator,remaining[k]) for k in (0,1))
                if not gain:
                    continue
                charge = max(delta[0]*problem['limit'][1],delta[1]*problem['limit'][0])
                better = choice is None or (charge==0 and (choice[2]!=0 or gain>choice[1])) or (
                    choice is not None and charge!=0 and choice[2]!=0 and gain*choice[2]>choice[1]*charge)
                if better:
                    choice = (i,gain,charge,fresh_nodes,fresh_features,after,added)
            if choice is None:
                break
            i,_,_,new_nodes,new_features,after,added = choice
            selected.append(i)
            selected_set.add(i)
            seen_nodes.update(new_nodes)
            seen_features.update(new_features)
            cost = list(after)
            values = [values[k]+added[k] for k in (0,1)]
        prefer(selected)
        checked = assess(problem,selected)
        achieved = min(checked['score'])
        trace.append(dict(target=str(target),achieved=str(achieved),selected=len(selected),cost=checked['cost'],proposalCount=used))
        return achieved

    if used+len(order)<=proposal_limit:
        used += len(order)
        for i in order:
            if assess(problem,[i])['feasible']:
                prefer([i])
    fill(Fraction(1))
    lower,upper = min(best['score']),Fraction(1)
    for _ in range(passes):
        if used+len(order)>proposal_limit or lower==upper:
            break
        target = (lower+upper)/2
        achieved = fill(target)
        if achieved>=target:
            lower=max(lower,target)
        else:
            # This is a search target, not a certified objective upper bound.
            upper=target
    final = assess(problem,best_selected)
    assert final==best
    return dict(selected=best_selected,cost=list(final['cost']),values=list(final['values']),
                score=[str(v) for v in final['score']],proposalCount=used,proposalLimit=proposal_limit,
                activeOffers=len(order),passes=trace,feasible=True,seedScore=[str(v) for v in assess(problem,problem.get('chosen',[]))['score']],
                heuristicUpperIsNotAnOptimalityBound=True,runtimeExecuted=False,productionAdoption=False)
