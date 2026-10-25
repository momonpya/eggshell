require 'json'
require 'digest'
require 'fileutils'

root = File.expand_path(__dir__)
parent = File.dirname(root)
source = File.join(parent, 'empty-search-20261025')
owners = File.join(parent, 'keyed-advice-20261025/scale-data/read-cache')
identity = 'eb5d3f9baf77963bfcfdc94afde22939b244236c8a6ef70bf4c12133b3058971'
data = File.join(root, 'scale-data-50000')
plugin = File.join(root, 'plugin')
abort 'keep earlier native preparation' if File.exist?(data) || File.exist?(plugin)
def clone(source, target)
  abort "clone failed: #{source}" unless system('/bin/cp', '-cR', source, target)
end
clone(File.join(source, 'scale-data-50000'), data)
indexes = File.join(data, 'read-cache', identity, 'indexes')
FileUtils.mkdir_p(indexes)
clone(File.join(owners, identity, 'indexes/window-owners'), indexes)
clone(File.join(source, 'plugin'), plugin)
launcher = File.join(plugin, 'bin/eggshelld')
File.unlink(launcher)
clone(File.join(root, 'eggshell'), launcher)
binary_hash = Digest::SHA256.file(File.join(root, 'eggshell')).hexdigest
abort 'plugin runtime mismatch' unless binary_hash == Digest::SHA256.file(launcher).hexdigest
record = {runtimeSha256: binary_hash, pluginLauncherSha256: binary_hash,
          originalCache: File.join(source, 'scale-data-50000'),
          windowOwners: File.join(owners, identity, 'indexes/window-owners'),
          method: 'APFS copy-on-write; original source DB and caches unchanged',
          answeringModelCalls: 0, seedCalls: 0, sourceEmbeddings: 0}
File.write(File.join(root, 'native-preparation.json'), JSON.pretty_generate(record)+"\n")
