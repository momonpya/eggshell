"""Preserve diagnostic advisory receipts across verified graph republication.

Only the source identity in an advisory frontier is rebound. Callers must first
verify unchanged authoritative values, root IDs/order and window identities.
Observation/completion receipts are never rewritten.
"""
import json


def rebind(claims, question, source_identity, target_identity):
    result = []
    frontiers = 0
    for claim in claims:
        if not claim.startswith('a:'):
            result.append(claim)
            continue
        recorded, frontier = json.loads(claim[2:])
        if recorded != question:
            result.append(claim)
            continue
        if frontier['identity'] != source_identity:
            raise ValueError('Advisory receipt belongs to a different source DB')
        if type(frontier['nextRoot']) is not int or frontier['nextRoot'] < 0:
            raise ValueError('Invalid advisory insertion frontier')
        frontiers += 1
        if source_identity == target_identity:
            result.append(claim)
        else:
            rebound = dict(frontier, identity=target_identity)
            result.append('a:' + json.dumps([recorded, rebound], ensure_ascii=False, separators=(',', ':')))
    if not frontiers:
        raise ValueError('No acknowledged frontier for this question/source')
    return result
