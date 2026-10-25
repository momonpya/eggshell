require 'json'
require 'digest'
root=File.expand_path(__dir__)
j=JSON.parse(File.read(root+'/review.json'))
entries=%w[sourceNumericalFiles sources generated linkedInputs evidence originalFiles guards].flat_map{|k|j.fetch(k)}+[j.fetch('numericalBoundary')]
entries=entries.uniq{|f|f.fetch('path')}
entries.each do |f|
  p=f.fetch('path');abort "changed #{p}" unless File.file?(p) && File.size(p)==f.fetch('bytes') && Digest::SHA256.file(p).hexdigest==f.fetch('sha256')
end
j.fetch('retirements').each{|f|abort 'retired helper remains' if File.exist?(f.fetch('path'))}
abort 'qualification overclaim' if j.fetch('adopted') || j.fetch('inclusiveTokenComparison') || j.fetch('nativeHookQualification')
abort 'resource ceiling exceeded' unless j.fetch('maximumAggregateRssKiB') < j.fetch('limitRssKiB')
result={checkedArtifacts:entries.size,changed:[],checkedOriginalRows:j.fetch('prepared').fetch('checkedRows'),adopted:false}
File.write(root+'/review.check.json',JSON.pretty_generate(result)+"\n")
puts JSON.generate(result)
