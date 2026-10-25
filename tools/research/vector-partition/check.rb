require 'json'
require 'digest'

path = File.expand_path('../../../docs/candidates/vector-partition-review.json', __dir__)
r = JSON.parse(File.read(path))
abort 'unqualified candidate adopted' unless r.fetch('adopted') == false && r.fetch('inclusiveTokenComparison') == false
abort 'incorrect exact-search claim' unless r.fetch('safeFloatPruningClaimed') == false
bindings = %w[sources originalFiles originalNumericalFiles completeScores generated linkedInputs evidence guards].flat_map { |k| r.fetch(k) }
bindings << r.fetch('helper')
bindings.uniq { |f| f.fetch('path') }.each do |f|
  p = f.fetch('path')
  abort "missing or changed evidence: #{p}" unless File.file?(p) && File.size(p) == f.fetch('bytes') &&
    Digest::SHA256.file(p).hexdigest == f.fetch('sha256')
end
r.fetch('sources').each do |f|
  p = File.join(__dir__, f.fetch('relative'))
  abort "checkpoint differs: #{p}" unless Digest::SHA256.file(p).hexdigest == f.fetch('sha256')
end
guards = r.fetch('guards').map { |f| [File.basename(f.fetch('path')), JSON.parse(File.read(f.fetch('path')))] }.to_h
%w[build-final trial].each do |name|
  g = guards.fetch(name + '.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('state') == 'finished' && g.fetch('exitCode') == 0 &&
    !g.fetch('guardTriggered') && g.fetch('ownedPids').empty?
end
abort 'memory ceiling exceeded' unless r.fetch('maximumAggregateRssKiB') <= 3670016
raw_path = r.fetch('evidence').find { |f| f.fetch('path').end_with?('/trial/result.json') }.fetch('path')
raw = JSON.parse(File.read(raw_path))
abort 'changed reference or eligibility' unless raw.fetch('queries').size == 11 && raw.fetch('cellSizes').sum == 50000 &&
  raw.fetch('queries').first.fetch('originalScalarBitsChecked') == 3125 &&
  raw.fetch('queries').first.fetch('storedFullProviderOwnerRankingChecked')
raw.fetch('queries').each do |q|
  keys = q.fetch('selection').fetch('keys')
  abort 'invalid nomination budget' unless keys.size == 3125 && keys.uniq.size == keys.size
  method = q.fetch('methods').find { |m| m.fetch('method') == 'learned-eligible' }
  method.fetch('windowRecall').each do |rec|
    abort 'recall not supported by nominated keys' unless (rec.fetch('expected') & keys) == rec.fetch('retained') &&
      rec.fetch('retained').size == rec.fetch('found')
  end
end
puts JSON.generate({evidenceBindings:bindings.map { |f| f.fetch('path') }.uniq.size,queries:11,
  scalarBitsChecked:3125,adopted:false,recordSha256:Digest::SHA256.file(path).hexdigest})
