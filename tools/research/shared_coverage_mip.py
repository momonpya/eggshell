"""Offline global diagnostic for the declared SharedCoverage surrogate.

HiGHS is an experiment-local dependency, never an Eggshell runtime dependency.
The optimizer receives only declared costs/closures/coverage. Optional required
DNF clauses are explicitly oracle-only diagnostics, not a retrieval policy.
Feasibility and benefits of returned offer sets are recomputed with integers.
Numerical solver bounds are not a formal arithmetic optimality certificate.
"""
import argparse
from fractions import Fraction
import json
import math
from pathlib import Path
import sys
import time


def weights(problem):
    return problem.get('weights', [p['weight'] for p in problem.get('pieces', ())])


def assess(problem, selected):
    if len(set(selected)) != len(selected) or any(i < 0 or i >= len(problem['offers']) for i in selected):
        raise ValueError('invalid or repeated offer')
    nodes = {n for i in selected for n in problem['offers'][i]['closure']}
    cues = {c for i in selected for c in problem['offers'][i]['covers']}
    cost = [problem['fixed'][k] + sum(problem['nodeCosts'][n][k] for n in nodes) for k in (0,1)]
    benefit = sum(weights(problem)[c] for c in cues)
    return dict(cost=cost,benefit=benefit,feasible=all(cost[k]<=problem['limit'][k] for k in (0,1)),nodes=sorted(nodes),cues=sorted(cues))


def satisfies(selected, required):
    chosen = set(selected)
    return all(any(all(any(i in chosen for i in cell) for cell in alternative)
                   for alternative in clause['alternatives']) for clause in required)


def solve(problem, highspy, numpy, directory, seconds=45, required=(), seed=None):
    directory = Path(directory)
    directory.mkdir(parents=True,exist_ok=False)
    u, n, c = len(problem['offers']), len(problem['nodeCosts']), len(weights(problem))
    extra = [alternative for clause in required for alternative in clause['alternatives']]
    cols = u+n+c+len(extra)
    scale = max(weights(problem), default=1) or 1
    coefficients = [w/scale for w in weights(problem)]
    rounding = sum((abs(Fraction.from_float(f)-Fraction(w,scale))
                    for w,f in zip(weights(problem),coefficients)),Fraction())
    starts, indices, values, lows, highs = [0], [], [], [], []
    inf = highspy.kHighsInf

    def row(terms, low=-inf, high=0):
        for index,value in terms:
            indices.append(index)
            values.append(value)
        starts.append(len(indices))
        lows.append(low)
        highs.append(high)

    node_users, cue_users = [[] for _ in range(n)], [[] for _ in range(c)]
    for i,offer in enumerate(problem['offers']):
        for node in set(offer['closure']):
            row([(i,1),(u+node,-1)])
            node_users[node].append(i)
        for cue in set(offer['covers']):
            row([(i,1),(u+n+cue,-1)])
            cue_users[cue].append(i)
    for node,users in enumerate(node_users):
        row([(u+node,1)]+[(i,-1) for i in users])
    for cue,users in enumerate(cue_users):
        row([(u+n+cue,1)]+[(i,-1) for i in users])
    for k in (0,1):
        row([(u+i,cost[k]) for i,cost in enumerate(problem['nodeCosts'])],
            high=problem['limit'][k]-problem['fixed'][k])
    next_extra = u+n+c
    for clause in required:
        owner_columns = []
        for alternative in clause['alternatives']:
            if not alternative or any(not cell or any(i<0 or i>=u for i in cell) for cell in alternative):
                raise ValueError('empty or invalid diagnostic coverage clause')
            owner_columns.append(next_extra)
            for cell in alternative:
                row([(next_extra,1)]+[(i,-1) for i in sorted(set(cell))])
            next_extra += 1
        row([(i,1) for i in owner_columns],low=1,high=inf)
    lp = highspy.HighsLp()
    lp.num_col_, lp.num_row_ = cols, len(lows)
    lp.sense_ = highspy.ObjSense.kMaximize
    lp.col_cost_ = numpy.array([0]*(u+n)+coefficients+[0]*len(extra),dtype=numpy.float64)
    lp.col_lower_, lp.col_upper_ = numpy.zeros(cols), numpy.ones(cols)
    lp.row_lower_, lp.row_upper_ = numpy.array(lows), numpy.array(highs)
    lp.a_matrix_.format_ = highspy.MatrixFormat.kRowwise
    lp.a_matrix_.start_ = numpy.array(starts,dtype=numpy.int32)
    lp.a_matrix_.index_ = numpy.array(indices,dtype=numpy.int32)
    lp.a_matrix_.value_ = numpy.array(values,dtype=numpy.float64)
    lp.integrality_ = ([highspy.HighsVarType.kInteger]*u +
                       [highspy.HighsVarType.kContinuous]*(n+c) +
                       [highspy.HighsVarType.kInteger]*len(extra))
    h = highspy.Highs()
    options = dict(threads=1,parallel='off',random_seed=0,time_limit=seconds,
                   mip_rel_gap=1e-8,mip_abs_gap=1e-7,log_to_console=False,
                   log_file=str(directory/'solver.log'))
    for key,value in options.items():
        assert h.setOptionValue(key,value)==highspy.HighsStatus.kOk,(key,value)
    assert h.passModel(lp)==highspy.HighsStatus.kOk
    h.writeModel(str(directory/'model.lp'))
    initial = list(problem.get('chosen', ())) if seed is None else list(seed)
    checked = assess(problem, initial)
    if not checked['feasible'] or not satisfies(initial,required):
        raise ValueError('diagnostic initial offer set is not feasible')
    initial_values = numpy.zeros(cols)
    initial_values[initial] = 1
    initial_values[[u+i for i in checked['nodes']]] = 1
    initial_values[[u+n+i for i in checked['cues']]] = 1
    for i,alternative in enumerate(extra):
        if all(any(j in initial for j in cell) for cell in alternative):
            initial_values[u+n+c+i]=1
    assert h.setSolution(cols,numpy.arange(cols,dtype=numpy.int32),initial_values)==highspy.HighsStatus.kOk
    before = time.monotonic()
    h.run()
    elapsed = time.monotonic()-before
    solution, info = h.getSolution(), h.getInfo()
    candidate = list(solution.col_value)
    if not solution.value_valid or len(candidate)!=cols or any(abs(v-round(v))>1e-6 for v in candidate[:u]):
        raise ValueError('solver returned no usable integral offer set')
    selected = [i for i in range(u) if candidate[i]>.5]
    exact = assess(problem,selected)
    if not exact['feasible'] or not satisfies(selected,required):
        raise ValueError('independent integer validation rejected the solution')
    result = dict(selected=selected,integerCheck=exact,
        baseline=checked,improvementRatio=exact['benefit']/checked['benefit']-1 if checked['benefit'] else None,
        status=h.modelStatusToString(h.getModelStatus()),seconds=elapsed,solverVersion=h.version(),
        numericalObjective=info.objective_function_value,scaledExactObjective=exact['benefit']/scale,
        numericalUpper=info.mip_dual_bound if math.isfinite(info.mip_dual_bound) else None,
        numericalRelativeGap=info.mip_gap if math.isfinite(info.mip_gap) else None,
        nodes=info.mip_node_count,rows=lp.num_row_,columns=cols,objectiveScale=scale,
        coefficientRoundingError=float(rounding),solverOptions=options,
        oracleDiagnostic=bool(required),formalOptimalityCertificate=False,
        numericalBoundCaveat='HiGHS tolerance-based bound; coefficient rounding recorded, exact feasibility/benefit independently recomputed.',
        runtimeExecuted=False,productionAdoption=False,answeringModelCalls=0)
    (directory/'result.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--problem',type=Path,required=True)
    parser.add_argument('--solver-path',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--seconds',type=float,default=45)
    parser.add_argument('--required',type=Path)
    parser.add_argument('--seed',type=Path)
    args = parser.parse_args()
    sys.path.insert(0,str(args.solver_path))
    import highspy
    import numpy
    read=lambda p:json.loads(p.read_text())
    result=solve(read(args.problem),highspy,numpy,args.output,args.seconds,
        read(args.required) if args.required else (),read(args.seed) if args.seed else None)
    print(json.dumps({k:result[k] for k in ['status','seconds','improvementRatio','numericalRelativeGap','oracleDiagnostic']}))


if __name__=='__main__':
    main()
