"""Reproduce actual selection, then change only the immutable payload cost basis."""
from pathlib import Path
import argparse,hashlib,json,re
from semantic_latency import save
from readme_trial import read,sha
from memory_guard import require_guard,code_sha

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--audit-root',type=Path,required=True)
parser.add_argument('--reference-root',type=Path,required=True)
parser.add_argument('--graph',type=Path,required=True)
parser.add_argument('--stages',type=int,nargs='+',required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
require_guard(dict(memoryGuardSha256=code_sha()))
OUT=args.audit_root;F=args.reference_root;graph=args.graph
assert not args.output.exists(), 'Preserve existing analysis; choose a fresh output path'
progress=args.output.with_suffix('.progress.json')
assert not progress.exists(), 'Preserve existing progress records'
verified=read(OUT/'run/result.json')
verifiedRows={r['stage']:r for r in verified['rows']}

def merge(ranges):
 result=[]
 for a,b in sorted(ranges):
  if result and a<=result[-1][1]:result[-1][1]=max(b,result[-1][1])
  else:result.append([a,b])
 return result

def covers(ranges,a,b):return any(c<=a and b<=d for c,d in merge(ranges))

def decode_offsets(raw):
 if not raw.startswith('"'):return raw,list(range(len(raw)+1))
 result=[];offsets=[];i=1
 while i<len(raw)-1:
  first=i
  if raw[i]=='\\':
   end=i+(6 if raw[i+1]=='u' else 2)
   if raw[i+1]=='u' and 0xd800<=int(raw[i+2:i+6],16)<=0xdbff and raw[end:end+2]=='\\u':end+=6
   char=json.loads('"'+raw[i:end]+'"')
  else:char=raw[i];end=i+1
  assert len(char)==1;result.append(char);offsets.append(first);i=end
 text=''.join(result);assert text==json.loads(raw);return text,offsets+[len(raw)-1]

def choose(costs,offers,weights,fixed,limit):
 closures=[set(o['closure']) for o in offers];cueSets=[set(o['covers']) for o in offers]
 def fit(selected,nodes,seen,cost,value):
  while True:
   best=None
   for i,(closure,cues) in enumerate(zip(closures,cueSets)):
    if i in selected:continue
    newNodes=closure-nodes;delta=tuple(sum(costs[n][k] for n in newNodes) for k in [0,1]);after=tuple(cost[k]+delta[k] for k in [0,1])
    if any(after[k]>limit[k] for k in [0,1]):continue
    gain=sum(weights[c] for c in cues-seen)
    if gain<=0:continue
    charge=max(delta[0]*limit[1],delta[1]*limit[0]);next=(i,gain,charge,newNodes,after)
    if best is None or (charge==0 and (best[2]!=0 or best[1]<gain)) or (charge!=0 and best[2]!=0 and best[1]*charge<gain*best[2]):best=next
   if best is None:return selected,cost,value
   i,gain,_,newNodes,cost=best;selected=selected+[i];nodes|=newNodes;seen|=cueSets[i];value+=gain
 greedy=fit([],set(),set(),tuple(fixed),0)
 best=greedy
 for i,closure in enumerate(closures):
  cost=tuple(fixed[k]+sum(costs[n][k] for n in closure) for k in [0,1]);value=sum(weights[c] for c in cueSets[i])
  if all(cost[k]<=limit[k] for k in [0,1]) and best[2]<value:best=([i],cost,value)
 return best

# Match actual atom bytes, independently of provider ids and graph node ordinals.
g=read(graph);atoms={}
for n in g[2]:
 if n[0]=='atom' and isinstance(n[1],str):
  h=hashlib.sha256(n[1].encode()).hexdigest()
  if h in atoms:assert atoms[h]==n[1]
  atoms[h]=n[1]
requirements=read(F/'native-question-requirements.json');results=[]
for stage in args.stages:
 case=OUT/f'run/stage{stage}';qualification=verifiedRows[stage];assert qualification['sameBody'] and qualification['sourceUnchanged'];assert sha(case/'audit.json')==qualification['auditSha256'];assert sha(case/'body.txt')==qualification['bodySha256']==qualification['referenceSha256'];audit=read(case/'audit.json');selections=[r['data'] for r in audit if r['kind']=='EGGSHELL_RANGE_SELECTION'];assert len(selections)==1;p=selections[0]
 weights=[x['weight'] for x in p['pieces']];old=choose(p['nodeCosts'],p['offers'],weights,p['fixed'],p['limit']);assert old[0]==p['chosen'] and list(old[1])==p['modeledCost'] and old[2]==p['benefit']
 sources=[atoms[f['sourceSha256']] for f in p['families']];assert all(len(text)==f['sourceChars'] for text,f in zip(sources,p['families']))
 fragments={};boundaries={};ambiguities=[]
 for unit,offer in zip(p['units'],p['offers']):
  family=unit['family'];f=p['families'][family]
  if not f['context']:continue
  assert len(offer['closure'])==1+len(unit['ranges']);assert offer['closure'][0]==family
  for (a,b),node in zip(unit['ranges'],offer['closure'][1:]):
   raw=sources[family][a:b];possible=[]
   for decoded in [False,True]:
    body=raw;didDecode=False
    if decoded:
     try:body=json.loads('"'+raw+'"');didDecode=True
     except ValueError:pass
    for compact in [False,True]:
     label=f'  CHARS [{a},{b})'+(' decoded\n' if didDecode else '\n') if compact else f'  ORIGINAL CHARS [{a},{b})\n'+('  DECODED JSON STRING DATA\n' if didDecode else '')
     if [len(label+body)+1,len((label+body).encode())+1]==p['nodeCosts'][node]:possible.append((didDecode,compact,body,label))
   # Cost identity follows the actual presentation. A failed decode is raw.
   possible=list(set(possible))
   if len(possible)!=1:
    ambiguities.append(dict(node=node,family=family,range=[a,b],possible=len(possible)));continue
   decoded,compact,body,label=possible[0];record=(family,a,b,decoded,body,label)
   assert node not in fragments or fragments[node]==record;fragments[node]=record;boundaries.setdefault((family,decoded),set()).update([a,b])
 costs=[];indices={};offers=[];fallback=[]
 def node_id(key,cost):
  if key not in indices:indices[key]=len(costs);costs.append(cost)
  else:assert costs[indices[key]]==cost
  return indices[key]
 for offer in p['offers']:
  closure=[]
  for node in offer['closure']:
   if node not in fragments:closure.append(node_id(('opaque',node),p['nodeCosts'][node]));continue
   family,a,b,decoded,body,label=fragments[node];cuts=[a]+sorted(x for x in boundaries[(family,decoded)] if a<x<b)+[b];cells=[]
   try:
    for first,last in zip(cuts,cuts[1:]):
     raw=sources[family][first:last];text=json.loads('"'+raw+'"') if decoded else raw;cells.append((first,last,raw,text))
    assert ''.join(c[3] for c in cells)==body
   except (ValueError,AssertionError):
    fallback.append(node);closure.append(node_id(('opaque',node),p['nodeCosts'][node]));continue
   closure.append(node_id(('caption',node),(len(label)+1,len(label.encode())+1)))
   for first,last,raw,text in cells:closure.append(node_id(('data',family,first,last,decoded,raw),(len(text),len(text.encode()))))
  offers.append(dict(closure=closure,covers=offer['covers']))
 # A complete offer keeps its exact cost; only cross-offer duplicate payload becomes shared.
 for before,after in zip(p['offers'],offers):
  for k in [0,1]:assert sum(p['nodeCosts'][n][k] for n in set(before['closure']))==sum(costs[n][k] for n in set(after['closure']))
 selectedNodes=set(n for i in old[0] for n in offers[i]['closure']);correctedCurrent=[p['fixed'][k]+sum(costs[n][k] for n in selectedNodes) for k in [0,1]]
 assert all(p['realCost'][k]<=correctedCurrent[k]<=p['modeledCost'][k] for k in [0,1])
 counter=choose(costs,offers,weights,p['fixed'],p['limit'])
 base=p['mandatoryPacketCost'];overheads=[];conditional=[list(c) for c in p['nodeCosts']];combined=[list(c) for c in costs]
 for family,(packet,data) in enumerate(zip(p['singletonPacketCosts'],p['templateDataCosts'])):
  delta=[max(0,packet[k]-base[k]-data[k]) for k in [0,1]];overheads.append(delta)
  conditional[family]=[conditional[family][k]+delta[k] for k in [0,1]]
  if ('opaque',family) in indices:
   i=indices[('opaque',family)];combined[i]=[combined[i][k]+delta[k] for k in [0,1]]
 conditionalResult=choose(conditional,p['offers'],weights,base,p['limit']);combinedResult=choose(combined,offers,weights,base,p['limit'])
 def model_cost(selected,costs,offers,fixed):
  nodes=set(n for i in selected for n in offers[i]['closure']);return [fixed[k]+sum(costs[n][k] for n in nodes) for k in [0,1]]
 currentConditional=model_cost(old[0],conditional,p['offers'],base);currentCombined=model_cost(old[0],combined,offers,base)
 blocks=[]
 for block in requirements['rows'][stage-1]['blocks']:
  owners=[]
  for family,f in enumerate(p['families']):
   if f['owner'] not in block['originalOwners']:continue
   text,offsets=decode_offsets(sources[family]);lines=text.splitlines(keepends=True);wanted=block['originalExcerpt'].splitlines();required=[]
   # Stored observations may use sed without line numbers or nl with numbers.
   # Locate the same original code before converting through the actual JSON offsets.
   prepared=[];offset=0
   for line in lines:
    m=re.match(r'^\s*(\d+)[\t :]+(.*?)(?:\r?\n)?$',line)
    body=m[2] if m else line.rstrip('\r\n');left=offset+(m.start(2) if m else 0)
    prepared.append((body.strip(),left+len(body)-len(body.lstrip()),left+len(body.rstrip())))
    offset+=len(line)
   occurrences=[]
   for start in range(len(prepared)-len(wanted)+1):
    if [x[0] for x in prepared[start:start+len(wanted)]]==[x.strip() for x in wanted]:
     occurrences.append([(block['first']+i,offsets[a],offsets[b]) for i,(_,a,b) in enumerate(prepared[start:start+len(wanted)]) if a<b])
   assert occurrences,(stage,block['name'],f['owner'],'No exact original code sequence')
   # This corpus has one occurrence per source result; ambiguity stays explicit.
   assert len(occurrences)==1,(stage,block['name'],f['owner'],'Repeated code: retain all alternative ranges before evaluating coverage')
   required=occurrences[0]
   def offered(selected):return merge([span for i in selected if p['units'][i]['family']==family for span in p['units'][i]['ranges']])
   allRange=offered(range(len(p['units'])));current=offered(old[0]);after=offered(counter[0]);conditionalRanges=offered(conditionalResult[0]);combinedRanges=offered(combinedResult[0]);complete=[i for i,u in enumerate(p['units']) if u['family']==family and all(covers(u['ranges'],a,b) for _,a,b in required)]
   owners.append(dict(owner=f['owner'],family=family,requiredOriginalRanges=required,allOffered=all(covers(allRange,a,b) for _,a,b in required),current=all(covers(current,a,b) for _,a,b in required),counterfactual=all(covers(after,a,b) for _,a,b in required),conditional=all(covers(conditionalRanges,a,b) for _,a,b in required),combined=all(covers(combinedRanges,a,b) for _,a,b in required),singleCompleteOffers=complete,minCompleteOfferCost=min((sum(p['nodeCosts'][n][0] for n in set(p['offers'][i]['closure'])) for i in complete),default=None)))
  blocks.append(dict(name=block['name'],owners=owners,current=any(o['current'] for o in owners),counterfactual=any(o['counterfactual'] for o in owners),allOffered=any(o['allOffered'] for o in owners),conditional=any(o['conditional'] for o in owners),combined=any(o['combined'] for o in owners)))
 result=dict(stage=stage,referenceSelectionExactlyReproduced=True,mandatoryPacketCost=base,singletonOverheads=overheads,materializedDataCost=p['materializedDataCost'],actualFrameCost=[p['realCost'][k]-p['materializedDataCost'][k] for k in [0,1]],conditionalCurrentCost=currentConditional,combinedCurrentCost=currentCombined,conditionalCounter=dict(selected=conditionalResult[0],cost=conditionalResult[1],benefit=conditionalResult[2],productionExecuted=False),combinedCounter=dict(selected=combinedResult[0],cost=combinedResult[1],benefit=combinedResult[2],productionExecuted=False),modeledCost=p['modeledCost'],realCost=p['realCost'],correctedCurrentCost=correctedCurrent,modeledOvercharge=[p['modeledCost'][k]-p['realCost'][k] for k in [0,1]],recoverablePayloadCharge=[p['modeledCost'][k]-correctedCurrent[k] for k in [0,1]],counterfactual=dict(selected=counter[0],cost=counter[1],benefit=counter[2],productionExecuted=False),ambiguousNodes=ambiguities,unseparableNodes=sorted(set(fallback)),blocks=blocks)
 results.append(result);save(progress,dict(rows=results,answeringModelCalls=0));print(json.dumps(dict(stage=stage,modeled=p['modeledCost'],actual=p['realCost'],shared=correctedCurrent,currentMissing=[b['name'] for b in blocks if not b['current']],counterMissing=[b['name'] for b in blocks if not b['counterfactual']],notOffered=[b['name'] for b in blocks if not b['allOffered']],conditionalMissing=[b['name'] for b in blocks if not b['conditional']],combinedMissing=[b['name'] for b in blocks if not b['combined']],conditionalCurrent=currentConditional,actualFrame=[p['realCost'][k]-p['materializedDataCost'][k] for k in [0,1]],fixed=p['fixed'],ambiguities=len(ambiguities))),flush=True)
save(args.output,dict(rows=results,graph=str(graph),graphSha256=sha(graph),runtimeBodyUnchanged=True,actualSelectionReproduced=True,counterfactualOnly=True,questionSpecificRuntimeRules=False,answeringModelCalls=0,productionAdoption=False,scriptSha256=sha(Path(__file__))))
