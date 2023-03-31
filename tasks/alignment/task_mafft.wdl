version 1.0

task mafft {
  input {
    Array[File] genomes
    Int cpu = 16
    Int disk_size = 100
    String docker = "quay.io/staphb/mafft:7.450"
  }
  command <<<
    # date and version control
    date | tee DATE
    echo "MAFFT $(mafft --version 2>&1 | grep v )" | tee VERSION

    # concatenate assemblies and align
    cat ~{sep=" " genomes} | sed 's/Consensus_//;s/.consensus_threshold.*//' > assemblies.fasta
    mafft --thread -~{cpu} assemblies.fasta > msa.fasta
  >>>
  output {
    String date = read_string("DATE")
    String version = read_string("VERSION")
    File msa = "msa.fasta"
  }
  runtime {
    docker: docker
    memory: "32 GB"
    cpu: cpu
    disks: "local-disk " + disk_size + " SSD"
    disk: disk_size + " GB"
    preemptible: 0
    maxRetries: 3
  }
}