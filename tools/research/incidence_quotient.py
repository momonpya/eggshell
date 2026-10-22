"""Exact SharedCoverage quotient by identical offer-incidence sets."""


def compress(problem):
    node_users = [set() for _ in problem['nodeCosts']]
    cue_weights = problem.get('weights', [p['weight'] for p in problem.get('pieces', ())])
    cue_users = [set() for _ in cue_weights]
    for i, offer in enumerate(problem['offers']):
        for node in offer['closure']:
            node_users[node].add(i)
        for cue in offer['covers']:
            cue_users[cue].add(i)
    node_groups, cue_groups = {}, {}
    for node, users in enumerate(node_users):
        if users:
            node_groups.setdefault(tuple(sorted(users)), []).append(node)
    for cue, users in enumerate(cue_users):
        if users:
            cue_groups.setdefault(tuple(sorted(users)), []).append(cue)
    costs, weights = [], []
    offers = [dict(closure=[], covers=[]) for _ in problem['offers']]
    for users, members in node_groups.items():
        index = len(costs)
        costs.append([sum(problem['nodeCosts'][n][k] for n in members) for k in (0,1)])
        for i in users:
            offers[i]['closure'].append(index)
    for users, members in cue_groups.items():
        index = len(weights)
        weights.append(sum(cue_weights[c] for c in members))
        for i in users:
            offers[i]['covers'].append(index)
    result = dict(nodeCosts=costs, weights=weights, offers=offers,
                  fixed=problem['fixed'],limit=problem['limit'],chosen=problem.get('chosen',[]))
    return result, dict(nodeGroups=list(node_groups.values()),cueGroups=list(cue_groups.values()),
                        unreachableCues=[i for i,users in enumerate(cue_users) if not users])
