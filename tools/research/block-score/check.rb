require 'json'
require 'digest'

record = File.expand_path('../../../docs/candidates/block-score-review.json', __dir__)
review = JSON.parse(File.read(record))
abort 'candidate adopted without token/quality evidence' unless review.fetch('adopted') == false &&
  review.fetch('inclusiveTokenComparison') == false && review.fetch('qualityQualification') == false
bindings = %w[sources originalFiles linkedInputs generated evidence guards].flat_map { |key| review.fetch(key) }
bindings.uniq { |item| item.fetch('path') }.each do |item|
  path = item.fetch('path')
  abort "missing/changed evidence: #{path}" unless File.file?(path) && File.size(path) == item.fetch('bytes') &&
    Digest::SHA256.file(path).hexdigest == item.fetch('sha256')
end
review.fetch('sources').each do |source|
  path = File.join(__dir__, source.fetch('relative'))
  abort "candidate checkpoint differs: #{path}" unless Digest::SHA256.file(path).hexdigest == source.fetch('sha256')
end
guards = review.fetch('guards').map { |item| [File.basename(item.fetch('path')), JSON.parse(File.read(item.fetch('path')))] }.to_h
%w[cleanup-build cleanup-relink compare-shared-0 compare-shared-1 compare-shared-2 payload-bounded native-configured].each do |name|
  guard = guards.fetch(name + '.guard.json')
  abort "failed final guard: #{name}" unless guard.fetch('state') == 'finished' && guard.fetch('exitCode') == 0 &&
    guard.fetch('guardTriggered') == false && guard.fetch('ownedPids').empty?
end
abort 'missing component repetition' unless review.fetch('comparisons').size == 3
review.fetch('comparisons').each do |result|
  abort 'component mismatch' unless result.fetch('allFloatBitsCoverageAndFullOrderEqual') &&
    result.fetch('residentBlockMisses') == 0 && result.fetch('residentBlockHits') == 3125 &&
    result.fetch('repeatStats').fetch('modelStarts') == 0
end
native = review.fetch('native')
abort 'wrong native cohort' unless native.fetch('pairs') == 3 && native.fetch('cases').size == 6
native.fetch('cases').each do |result|
  abort 'native deadline or semantic failure' unless result.fetch('totalMs') < 30000 &&
    result.fetch('exitCode') == 0 && result.fetch('replyComplete') && result.fetch('validStratum') &&
    result.fetch('search').fetch('trace').fetch('semantic') == 'completed' &&
    result.fetch('search').fetch('trace').fetch('warmRequests') == 0
end
abort 'same-question body changed' unless review.fetch('nativeBodyComparisons').all? { |result|
  result.fetch('equal') && result.fetch('reference').fetch('sha256') == result.fetch('candidate').fetch('sha256') &&
    result.fetch('reference').fetch('bytes') == result.fetch('candidate').fetch('bytes') }
abort 'aggregate memory ceiling exceeded' unless review.fetch('maximumAggregateRssKiB') <= 3670016
puts JSON.generate({evidenceBindings:bindings.map { |item| item.fetch('path') }.uniq.size,
  componentRepetitions:3,nativeCalls:6,adopted:false,recordSha256:Digest::SHA256.file(record).hexdigest})
