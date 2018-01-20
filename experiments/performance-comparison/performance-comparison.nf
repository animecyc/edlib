#!/usr/bin/env nextflow

params.numTests = 1  // TODO: actually use this. Generate duplicate tasks, and then average them later.
params.inputDataDir = '../../test_data'

//------- Experiments to conduct. --------//
// Experiment is of shape: [
//   file(query)
//   file(target)
//   mode - 'HW', 'NW' or 'SHW'.
//   k - max boundary for edit distance.
//   path - 0 if we are looking only for edit distance, 1 if we are also looking for alignment path.
// ]

Channel.fromPath(params.inputDataDir + '/Enterobacteria_Phage_1/mutated_*_perc.fasta')
  .combine([[file(params.inputDataDir + '/Enterobacteria_Phage_1/Enterobacteria_phage_1.fasta'), 'NW', -1]])
  .combine([0, 1])  // Both with path and without.
  .tap{enterobacteriaEdlib}.tap{enterobacteriaSeqan}
  .filter{it[4] == 0}.tap{enterobacteriaParasail}  // Parasail can't find path, so skip that.

Channel.fromPath(params.inputDataDir + '/E_coli_DH1/mason_illumina_read_10kbp/*.fasta')
  .combine([[file(params.inputDataDir + '/E_coli_DH1/e_coli_DH1.fasta'), 'HW', -1]])
  .combine([0, 1])  // Both with path and without.
  .tap{eColiInfixEdlib}
  .filter{it[4] == 0}.tap{eColiInfixSeqan}  // Seqan takes too much memory to find path, so skip.

edlibTasks = enterobacteriaEdlib.mix(eColiInfixEdlib)
seqanTasks = enterobacteriaSeqan.mix(eColiInfixSeqan)
parasailTasks = enterobacteriaParasail
//-----------------------------------------//

// TODO: Maybe have just one process, take aligner as an extra parameter, and then
//       have IF clauses to choose aligner?

process edlib {
  input:
  set file(query), file(target), mode, k, path from edlibTasks

  output:
  set file(query), file(target), mode, k, path, stdout into edlibResults

  shell:
  // TODO: Now I print CIG_STD because there is no other way to get score. If I had something like
  // -f NONE that still prints score I could avoid printing alignment, which can be very big.
  '''
  if [ !{path} = 0 ]; then
      output=$(edlib-aligner -m !{mode} -k !{k} !{query} !{target})
      score=$(echo "$output" | grep "#0:" | cut -d " " -f2)
  else
      output=$(edlib-aligner -m !{mode} -p -f CIG_STD -k !{k} !{query} !{target})
      score=$(echo "$output" | grep "score =" | cut -d "=" -f2)
  fi
  time=$(echo "$output" | grep "Cpu time of searching" | cut -d " " -f5)
  echo $time $score
  '''
}

edlibResults.subscribe {
  println "edlib: $it"
}

process parasail {
  input:
  set file(query), file(target), mode, k, path from parasailTasks

  output:
  set file(query), file(target), mode, k, path, stdout into parasailResults

  when:
  path == 0 && mode == 'NW'  // Parasail 1.1 can not find alignment path and supports only 'NW' mode.

  shell:
  '''
  output=$(parasail_aligner -t 1 -d -e 1 -o 1 -M 0 -X 1 -a nw_striped_32 -f !{target} -q !{query})
  time=$(echo "$output" | grep "alignment time" | cut -d ":" -f2 | cut -d " " -f2)
  score=$(($(head -n 1 parasail.csv | cut -d "," -f5) * -1))
  rm parasail.csv
  echo $time $score
  '''
}

parasailResults.subscribe {
  println "parasail: $it"
}
