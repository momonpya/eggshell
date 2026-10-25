require 'json'
root=File.expand_path(__dir__)
guard='/Users/ovm/.codex/experiments/eggshell/study-resources-20261024/controller/StudyMain'
3.times do |index|
  log=File.join(root,"benchmark-#{index}.log")
  abort 'preserve previous benchmark log' if File.exist?(log)
  abort "benchmark #{index} failed" unless system(guard,'guard',File.join(root,"benchmark-#{index}.settings.json"),out:log,err:log)
  summary=JSON.parse(File.read(File.join(root,"benchmark-#{index}/summary.json")))
  puts JSON.generate({repetition:index,cases:summary.fetch('cases').length,
    completeSequencesEqual:summary.fetch('cases').all?{|c|c.fetch('completeSequencesEqual')}})
  STDOUT.flush
end
