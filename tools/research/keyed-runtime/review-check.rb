require 'json'
require 'digest'

root = File.expand_path(__dir__)
review = JSON.parse(File.read(File.join(root,'review.json')))
artifacts = %w[generated linkedInputs evidence originalFiles].flat_map { |name| review.fetch(name) }
artifacts += [review.fetch('runtime'),review.fetch('pluginLauncher'),review.fetch('integrationPatch')]
artifacts += review.fetch('guards').map { |guard| guard.fetch('artifact') }
artifacts += review.fetch('sources').map { |source| {'path'=>source.fetch('source'),'bytes'=>source.fetch('bytes'),'sha256'=>source.fetch('sha256')} }
artifacts = artifacts.uniq { |entry| entry.fetch('path') }
artifacts.each do |entry|
  path = entry.fetch('path')
  abort "changed artifact #{path}" unless File.file?(path) && File.size(path)==entry.fetch('bytes') &&
    Digest::SHA256.file(path).hexdigest == entry.fetch('sha256')
end
review.fetch('retirements').each { |entry| abort "retired executable remains #{entry['path']}" if File.exist?(entry.fetch('path')) }
abort 'adoption status changed' unless review.fetch('adopted') == false && review.fetch('inclusiveTokenComparison') == false
abort 'resource guard exceeded' unless review.fetch('maximumAggregateRssKiB') < review.fetch('limitRssKiB')
abort 'native connection gate failed' unless review.fetch('nativeConnectionGate')
abort 'position mapping changed results' unless review.fetch('linearProjection').fetch('sameProviderResponseBytes')
result = {checkedArtifacts: artifacts.length, changed: [], nativeSemanticConnection: true,
  sourceHashesUnchanged: review.fetch('originalFilesUnchanged'),adopted: false,archivesCreated: false}
File.write(File.join(root,'review.check.json'),JSON.pretty_generate(result)+"\n")
puts JSON.generate(result)
