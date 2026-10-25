require 'json'
require 'digest'
root=File.expand_path(__dir__)
j=JSON.parse(File.read(File.join(root,'review.json')))
entries=%w[sources generated linkedInputs evidence originalFiles guards].flat_map{|k|j.fetch(k)}
entries+=[j.fetch('runtime'),j.fetch('pluginLauncher'),j.fetch('integrationPatch'),j.fetch('numericalBoundary')]
entries=entries.uniq{|f|f.fetch('path')}
entries.each do |f|
  p=f.fetch('path');abort "changed #{p}" unless File.file?(p)&&File.size(p)==f.fetch('bytes')&&Digest::SHA256.file(p).hexdigest==f.fetch('sha256')
end
j.fetch('retirements').each{|f|abort "retired executable remains #{f['path']}" if File.exist?(f.fetch('path'))}
abort 'adoption claim' unless !j.fetch('adopted')&&!j.fetch('inclusiveTokenComparison')
abort 'native body mismatch' unless j.fetch('nativeBodyBytesEqual')
abort 'resource ceiling exceeded' unless j.fetch('maximumAggregateRssKiB')<j.fetch('limitRssKiB')
result={checkedArtifacts:entries.length,changed:[],nativeBodyBytesEqual:true,adopted:false}
File.write(File.join(root,'review.check.json'),JSON.pretty_generate(result)+"\n")
puts JSON.generate(result)
