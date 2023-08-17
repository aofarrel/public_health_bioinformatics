version 1.0

task lyveset {
  input {
    Array[File] read1
    Array[File] read2
    File reference_genome
    String dataset_name
    String docker_image = "us-docker.pkg.dev/general-theiagen/staphb/lyveset:1.1.4f"
    Int memory = 64
    Int cpu = 16
    Int disk_size = 100
    # Lyve-SET Parameters
    ##COMMON OPTIONS
    ##--allowedFlanking  0              allowed flanking distance in bp.
    ##                                  Nucleotides this close together cannot be
    ##                                  considered as high-quality.
    ##--min_alt_frac     0.75           The percent consensus that needs
    ##                                  to be reached before a SNP is called.
    ##                                  Otherwise, 'N'
    ##--min_coverage     10             Minimum coverage needed before a
    ##                                  SNP is called. Otherwise, 'N'
    ##--presets          ""             See presets.conf for more information
    ##--numcpus          1              number of cpus
    ##PERFORM CERTAIN STEPS
    ##--mask-phages                  Search for and mask phages in the reference genome
    ##--mask-cliffs                  Search for and mask 'Cliffs' in pileups
    ##
    ##SKIP CERTAIN STEPS
    ##--nomatrix                     Do not create an hqSNP matrix
    ##--nomsa                        Do not make a multiple sequence alignment
    ##--notrees                      Do not make phylogenies
    ##--singleend                    Treat everything like single-end. Useful
    ##                               for when you think there is a single-
    ##                               end/paired-end bias.
    ##OTHER SHORTCUTS
    ##--fast                         Shorthand for --downsample --mapper snap --nomask-phages
    ##                                             --nomask-cliffs --sample-sites
    ##--downsample                   Downsample all reads to 50x. Approximated according
    ##                               to the ref genome assembly
    ##--sample-sites                 Randomly choose a genome and find SNPs in a quick
    ##                               and dirty way. Then on the SNP-calling stage,
    ##                               only interrogate those sites for SNPs for each
    ##                               genome (including the randomly-sampled genome).
    ##
    ##MODULES
    ##--read_cleaner none            Which read cleaner? Choices: none, CGP, BayesHammer
    ##--mapper       smalt           Which mapper? Choices: smalt, snap
    ##--snpcaller    varscan         Which SNP caller? Choices: varscan, vcftools
    Int allowedFlanking = 0
    Float min_alt_frac = 0.75
    Int min_coverage = 10
    String? presets
    Boolean mask_phages = false
    Boolean mask_cliffs = false
    Boolean nomatrix = false
    Boolean nomsa = false
    Boolean notrees = false
    # Boolean singleend = false -- currently written for PE read data only
    Boolean fast = false
    Boolean downsample = false
    Boolean sample_sites = false
    String read_cleaner = "CGP"
    String? mapper
    String? snpcaller
  }
  command <<<
    date | tee DATE

    # set bash arrays based on inputs to ensure read arrays are of equal length
    read1_array=(~{sep=' ' read1})
    read1_array_len=$(echo "${#read1[@]}")
    read2_array=(~{sep=' ' read2})
    read2_array_len=$(echo "${#read2[@]}")

    if [ "$read1_array_len" -ne "$read2_array_len" ]; then
      echo "read1 array (length: $read1_array_len) and read2 index array (length: $read2_array_len) are of unequal length." >&2
      exit 1
    fi

    # create lyvset project
    set_manage.pl --create ~{dataset_name}

    # This FASTQ file re-naming strategy is necessary due to filename parsing in shuffleSplitReads.pl here: https://github.com/lskatz/lyve-SET/blob/v1.1.4f/scripts/shuffleSplitReads.pl#L34
    # Curtis' interpretation of perl code:
    # It first checks for a pattern like '_R1_' or '_R2_', and if found, sets the $readNumber variable to 1 or 2 respectively.
    # If that pattern is not found, it checks for a pattern like '_1.f' or '_2.f', again setting the $readNumber accordingly.
    # If neither pattern is matched, it raises an error indicating that the read number could not be parsed from the filename.

    mkdir input-fastqs

    # copy FASTQs to input-fastqs/; rename if files end in "_R1.fastq.gz" or "_R2.fastq.gz"
    # read1
    for index in "${!read1_array[@]}"; do
      # if the R1 FASTQ filenames end in "_R1.fastq.gz"  rename the files to match lyveset naming convention
      if [[ ${read1_array[$index]} =~ _R1.fastq.gz$ ]]; then
        FASTQ_BASENAME=$(basename "${read1_array[$index]}")
        echo "DEBUG: renaming ${FASTQ_BASENAME} to ${FASTQ_BASENAME//_R1.fastq.gz/_1.fastq.gz}"
        cp -v "${read1_array[$index]}" "input-fastqs/${FASTQ_BASENAME//_R1.fastq.gz/_1.fastq.gz}"
      else
        cp -v "${read1_array[$index]}" input-fastqs/
      fi
    done

    # read2
    for index in "${!read2_array[@]}"; do
      if [[ ${read2_array[$index]} =~ _R2.fastq.gz$ ]]; then
        FASTQ_BASENAME=$(basename "${read2_array[$index]}")
        echo "DEBUG: renaming ${FASTQ_BASENAME} to ${FASTQ_BASENAME//_R2.fastq.gz/_2.fastq.gz}"
        cp -v "${read2_array[$index]}" "input-fastqs/${FASTQ_BASENAME//_R2.fastq.gz/_2.fastq.gz}"
      else
        cp -v "${read2_array[$index]}" input-fastqs/
      fi
    done

    echo "DEBUG: merging R1 and R2 FASTQ files into interleaved FASTQ files with shuffleSplitReads.pl now..."
    shuffleSplitReads.pl --numcpus ~{cpu} -o "./~{dataset_name}/reads" input-fastqs/*.fastq.gz
    
    # make directory for reference genome and copy reference genome into it. Also rename to reference.fasta
    mkdir -v ~{dataset_name}/ref/
    cp -v ~{reference_genome} ~{dataset_name}/ref/reference.fasta

    # launch lyveSET workflow now that everything is set up
    launch_set.pl --numcpus ~{cpu} \
    --allowedFlanking ~{allowedFlanking} \
    --min_alt_frac ~{min_alt_frac} \
    --min_coverage ~{min_coverage} \
    ~{'--presets ' + presets} \
    ~{true='--mask-phages' false='' mask_phages} \
    ~{true='--mask-cliffs' false='' mask_cliffs} \
    ~{true='--nomatrix' false='' nomatrix} \
    ~{true='--nomsa' false='' nomsa} \
    ~{true='--notrees' false='' notrees} \
    ~{true='--fast' false='' fast} \
    ~{true='--downsample' false='' downsample} \
    ~{true='--sample-sites' false='' sample_sites} \
    ~{'--read_cleaner ' + read_cleaner} \
    ~{'--mapper ' + mapper} \
    ~{'--snpcaller ' + snpcaller} \
     -ref ~{dataset_name}/ref/reference.fasta ~{dataset_name}
    
    # rename tree file to nwk file ending
    if [ -f ~{dataset_name}/msa/out.RAxML_bipartitions ]; then
      mv ~{dataset_name}/msa/out.RAxML_bipartitions ~{dataset_name}/msa/out.RAxML_bipartitions.nwk
    fi

  >>>
  output {
    String lyveset_docker_image = docker_image
    File? lyveset_pairwise_matrix = "~{dataset_name}/msa/out.pairwiseMatrix.tsv"
    File? lyveset_raxml_tree = "~{dataset_name}/msa/out.RAxML_bipartitions.nwk"
    File? lyveset_pooled_snps_vcf = "~{dataset_name}/msa/out.pooled.snps.vcf.gz"
    File? lyveset_filtered_matrix = "~{dataset_name}/msa/out.filteredMatrix.tsv"
    File? lyveset_alignment_fasta = "~{dataset_name}/msa/out.aln.fas"
    File? lyveset_reference_fasta = "~{dataset_name}/ref/reference.fasta"
    File? lyveset_masked_regions = "~{dataset_name}/reference/maskedRegions.bed"
    #TODO CHECK THESE OUTPUT FILES, MAKE SURE THEY ARE CORRECT
    Array[File]? lyveset_msa_outputs = glob("~{dataset_name}/msa/out*")
    Array[File]? lyveset_log_outputs = glob("~{dataset_name}/log/*")
    Array[File]? lyveset_reference_outputs = glob("~{dataset_name}/reference/*")
    Array[File]? lyveset_bam_outputs = glob("~{dataset_name}/bam/*.bam*")
    Array[File]? lyveset_vcf_outputs = glob("~{dataset_name}/vcf/*.vcf*")
    File lyveset_log = stdout()
  }
  runtime {
    docker: docker_image
    memory: "~{memory} GB"
    cpu: cpu
    disks: "local-disk ~{disk_size} SSD"
    preemptible: 0
    maxRetries: 2
  }
}
