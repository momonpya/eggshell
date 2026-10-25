require 'json'
require 'digest'
require 'shellwords'

root = File.expand_path(__dir__)
parent = File.dirname(root)
def read(path)
  JSON.parse(File.read(path))
end
def artifact(path)
  abort "missing artifact #{path}" unless File.file?(path)
  {path: path, bytes: File.size(path), sha256: Digest::SHA256.file(path).hexdigest}
end
before = read(File.join(parent,'keyed-advice-20261025/originals-before.json'))
after = before.fetch('files').map { |entry| artifact(entry.fetch('path')) }
abort 'original DB or lexical files changed' unless before.fetch('files').zip(after).all? do |a,b|
  a.fetch('bytes') == b.fetch(:bytes) && a.fetch('sha256') == b.fetch(:sha256)
end
File.write(File.join(root,'originals-after.json'),JSON.pretty_generate({files: after})+"\n")
summary = read(File.join(root,'native-linear-50000/summary.json'))
initial = read(File.join(root,'native-50000/summary.json'))
guards = Dir.glob(File.join(root,'*.guard.json')).sort.map { |path| [path,read(path)] }
abort 'live experiment guard' unless guards.all? { |_,g| g.fetch('state') == 'finished' && g.fetch('ownedPids').empty? }
terminal = %w[build-linear-projection.guard.json audit-linear.guard.json audit-linear-fixture.guard.json native-linear-50000.guard.json provider-linear-probe.guard.json]
terminal.each do |name|
  value = read(File.join(root,name))
  abort "unsuccessful final guard #{name}" unless value.fetch('exitCode') == 0 && !value.fetch('guardTriggered')
end
native = summary.fetch('cases').map do |entry|
  stages = entry.fetch('publication').fetch('stages')
  keyed = stages.select { |s| s.fetch('name').start_with?('keyed-') }.map do |s|
    {name: s.fetch('name'), record: s.fetch('record')}
  end
  entry.select { |key,_| %w[pair phase historyBefore validStratum question hookMs startupMs totalMs exitCode replyComplete originalBody bodyBytes bodySha256 acknowledgedHistory search].include?(key) }.merge('keyedStages' => keyed)
end
sources = read(File.join(root,'export-final/sources.json'))
generated = Dir.glob(File.join(root,'*.{o,c,rsp}')).sort.map { |path| artifact(path) }
linked = Shellwords.split(File.read(File.join(root,'runtime.rsp'))).select { |p| File.file?(p) }.uniq.sort.map { |path| artifact(path) }
evidence = Dir.glob(File.join(root,'*.{json,log,rb,md}')).sort.reject { |path| %w[review.json review.check.json].include?(File.basename(path)) }.map { |path| artifact(path) }
%w[native-50000 native-linear-50000 provider-probe provider-linear-probe].each do |folder|
  evidence += Dir.glob(File.join(root,folder,'**/*')).select { |p| File.file?(p) }.sort.map { |path| artifact(path) }
end
evidence += Dir.glob(File.join(root,'audit-linear-fixture/**/*.json')).sort.map { |path| artifact(path) }
receipt_ids = (summary.fetch('cases')+initial.fetch('cases')).map { |c| c.fetch('publication').fetch('id') }
%w[provider-probe provider-linear-probe].each do |folder|
  receipt_ids << read(File.join(root,folder,'result.json')).fetch('receipt')
end
receipt_ids.uniq.each do |id|
  evidence += Dir.glob(File.join(root,'scale-data-50000/receipts',id,'*.json')).sort.map { |path| artifact(path) }
end
same_provider = File.binread(File.join(root,'provider-probe/response.jsonl')) == File.binread(File.join(root,'provider-linear-probe/response.jsonl'))
abort 'linear projection changed the provider response' unless same_provider
embedding = File.join(root,'checkout/runtime/embedding.py')
reference_embedding = File.join(parent,'keyed-advice-20261025/checkout/runtime/embedding.py')
abort 'numerical boundary source changed' unless Digest::SHA256.file(embedding).hexdigest == Digest::SHA256.file(reference_embedding).hexdigest
review = {
  candidate: 'source-scoped-routed-native-discovery', baseCommit: 'eebe30147fe0fdc8bf524a180b03fd4a36fb7362',
  branch: 'hook-ingress-supervisor', parentCheckout: File.join(parent,'keyed-advice-20261025/checkout'),
  adopted: false, productRuntimeChanged: false, readmeClaimsChanged: false, phases0Through6: 'active',
  implementation: 'Lean policy, source-scoped protocol, original-position validation and atomic router maintenance; existing numerical boundary unchanged',
  runtime: artifact(File.join(root,'eggshell')), pluginLauncher: artifact(File.join(root,'plugin-linear/bin/eggshelld')),
  answeringModelCalls: 0, seedCalls: 0, sourceEmbeddingCalls: 0, queryEmbeddings: 'existing MiniLM private query-cache path; no token-saving claim',
  newPythonImplementation: false, numericalBoundary: artifact(embedding),
  inclusiveTokenComparison: false, answerQualityQualification: false,
  requiredOriginalDeliveryQualification: false, millionWindowQualification: false, p99Qualification: false,
  policy: {maxLeaves: 128, maxPhysicalPostingRows: 8192, partialCoverageExplicit: true,
           equalityAuthority: 'complete e-class recognition, independent of routed advisory domain',
           routingUpdate: 'exact matrix head; explicit atomic full replacement; unchanged writes zero',
           unresolvedScaleCosts: ['full common lexical postings','full route rebuild on matrix changes','federated global catalogue']},
  sources: sources, integrationPatch: artifact(File.join(root,'export-final/integration.patch')),
  componentFixture: read(File.join(root,'audit-linear-fixture/result.json')),
  linearProjection: {ordinaryLeanTheorem: 'originalOwners_compiled',sameProviderResponseBytes: same_provider,
    before: read(File.join(root,'provider-probe/result.json')),after: read(File.join(root,'provider-linear-probe/result.json'))},
  initialConnectionFailure: initial.fetch('cases').map { |c| c.select { |k,_| %w[phase totalMs search bodyBytes].include?(k) } },
  nativeConnectionGate: summary.fetch('cases').all? { |c| c.fetch('validStratum') && c.fetch('totalMs') < 30000 && c.fetch('search').fetch('trace').fetch('semantic') == 'completed' },
  native: native, source: summary.fetch('source'), preparation: read(File.join(root,'native-50000/private-warm.stdout.json')),
  repeatedPreparation: read(File.join(root,'native-50000/repeat-warm.stdout.json')),
  preparationReused: read(File.join(root,'native-linear-50000/preparation-reuse.json')),
  originalFiles: after, originalFilesUnchanged: true, generated: generated, linkedInputs: linked,
  evidence: evidence, guards: guards.map { |path,g| {artifact: artifact(path), exitCode: g.fetch('exitCode'), peakRssKiB: g.fetch('sampledPeakRssKiB')} },
  maximumAggregateRssKiB: guards.map { |_,g| g.fetch('sampledPeakRssKiB') }.max,
  limitRssKiB: 3670016, userCeilingRssKiB: 4194304,
  failedAttempts: ['reserved local identifier and multiline record syntax during integration compile',
    'ambiguous SearchProvider Options during provider compile',
    'old ContractAudit required full catalogue and old preflight; actual checks replaced with scoped/original boundary checks',
    'fixture meta imports missing; include Lean before compiling final fixture',
    'initial native connection still timed out because restoring lexical positions repeatedly walked the full linked list; replace by one array with exact Lean proof'],
  limitations: ['historical fixed-question router top-eight overlap was zero; not rerun for the new native producer and not a required-history recall measurement',
    'native scale fixture is one synthetic question and one first/continued pair, not human required-original recall or token qualification',
    'router scalar subset reads remain; contiguous block scorer not yet connected',
    'bounded recommendations do not claim complete semantic recall',
    'multi-DB protocol component test does not qualify the native federated path',
    'incremental routing deltas, compaction, hot-key continuation, million-scale preparation and shared multi-process tests remain',
    'MCP capture privacy, real server use, all topics/both laps matched inclusive tokens and quality, and paper remain'],
  retirements: File.exist?(File.join(root,'retirements.json')) ? read(File.join(root,'retirements.json')) : [],
  archivesCreated: false, nextAction: 'remove remaining common-posting and routed-row IO costs, add incremental route updates, and validate needed original evidence before matched token trials or adoption'
}
File.write(File.join(root,'review.json'),JSON.pretty_generate(review)+"\n")
puts JSON.generate({sourceCount: sources.length, artifacts: generated.length+linked.length+evidence.length,
  maximumAggregateRssKiB: review.fetch(:maximumAggregateRssKiB), cases: native.map { |c| c.select { |k,_| %w[phase totalMs bodyBytes].include?(k) } }})
