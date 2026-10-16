nextflow.enable.dsl = 2

params.outdir = "results/rnaseq_airway_raw"
params.samplesheet = "${projectDir}/analysis/airway_samples.tsv"
params.threads = 2
params.max_forks = 1
params.download_forks = 4
params.download_retries = 20
params.download_timeout = 3600
params.ensembl_release = "112"
params.container_image = "seqcheckflow-rnaseq:latest"
params.multiqc_container_image = "multiqc/multiqc:v1.27@sha256:b4c30167e87ecb120925792c20c4c98d06076dde5f6ba9af48dda792fa549225"

process DOWNLOAD_READS {
    container params.container_image
    cpus 1
    maxForks params.download_forks
    publishDir "${params.outdir}/raw", mode: "copy"

    input:
    tuple val(meta), val(run)

    output:
    tuple val(meta),
          path("${meta.sample}_R1.fastq.gz"),
          path("${meta.sample}_R2.fastq.gz"),
          path("${meta.sample}.download.tsv")

    script:
    """
    set -euo pipefail
    read1_md5=''
    read2_md5=''
    read1_bytes=''
    read2_bytes=''
    if curl --retry 5 --retry-all-errors --retry-delay 3 --retry-max-time 120 -fsSL \\
      'https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${run}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,fastq_bytes&format=tsv' \\
      -o run_info.tsv; then
      IFS=';' read -r -a url_list <<< "\$(awk -F '\\t' 'NR == 2 { print \$2 }' run_info.tsv)"
      IFS=';' read -r -a md5_list <<< "\$(awk -F '\\t' 'NR == 2 { print \$3 }' run_info.tsv)"
      IFS=';' read -r -a size_list <<< "\$(awk -F '\\t' 'NR == 2 { print \$4 }' run_info.tsv)"
      for index in "\${!url_list[@]}"; do
        case "\${url_list[\$index]}" in
          *_1.fastq.gz) read1="\${url_list[\$index]}"; read1_md5="\${md5_list[\$index]:-}"; read1_bytes="\${size_list[\$index]:-}" ;;
          *_2.fastq.gz) read2="\${url_list[\$index]}"; read2_md5="\${md5_list[\$index]:-}"; read2_bytes="\${size_list[\$index]:-}" ;;
        esac
      done
    else
      case '${run}' in
        SRR10395[0-9][0-9])
          shard=00\$(printf '%s' '${run}' | rev | cut -c 1)
          base="ftp.sra.ebi.ac.uk/vol1/fastq/SRR103/\$shard/${run}"
          read1="\$base/${run}_1.fastq.gz"
          read2="\$base/${run}_2.fastq.gz"
          ;;
        *)
          echo "ENA metadata unavailable and no direct mirror fallback is configured for ${run}" >&2
          exit 1
          ;;
      esac
    fi
    if [ -z "\$read1" ] || [ -z "\$read2" ]; then
      echo "ENA did not provide paired FASTQ files for ${run}" >&2
      exit 1
    fi
    download_with_resume() {
      url=\$1
      output=\$2
      expected_bytes=\$3
      expected_md5=\$4
      part="\$output.part"
      attempt=1
      while ! curl --fail --location --retry 3 --retry-all-errors --retry-delay 5 \\
        --connect-timeout 60 --max-time ${params.download_timeout} \\
        --continue-at - --output "\$part" "https://\$url"; do
        if (( attempt >= ${params.download_retries} )); then
          echo "Download failed after \$attempt attempts: \$url" >&2
          return 1
        fi
        attempt=\$((attempt + 1))
        sleep 5
      done
      actual_bytes=\$(stat -c '%s' "\$part")
      if [[ -n "\$expected_bytes" && "\$actual_bytes" != "\$expected_bytes" ]]; then
        echo "Expected \$expected_bytes bytes from \$url, got \$actual_bytes" >&2
        return 1
      fi
      gzip -t "\$part"
      if [[ -n "\$expected_md5" ]]; then
        printf '%s  %s\\n' "\$expected_md5" "\$part" | md5sum -c -
      fi
      mv "\$part" "\$output"
    }

    download_with_resume "\$read1" "${meta.sample}_R1.fastq.gz" "\$read1_bytes" "\$read1_md5"
    download_with_resume "\$read2" "${meta.sample}_R2.fastq.gz" "\$read2_bytes" "\$read2_md5"
    read1_bytes=\$(stat -c '%s' "${meta.sample}_R1.fastq.gz")
    read2_bytes=\$(stat -c '%s' "${meta.sample}_R2.fastq.gz")
    read1_md5=\$(md5sum "${meta.sample}_R1.fastq.gz" | cut -d ' ' -f 1)
    read2_md5=\$(md5sum "${meta.sample}_R2.fastq.gz" | cut -d ' ' -f 1)
    printf 'sample\\trun\\tread1_url\\tread2_url\\tread1_bytes\\tread2_bytes\\tread1_md5\\tread2_md5\\n' > '${meta.sample}.download.tsv'
    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \\
      '${meta.sample}' '${run}' "\$read1" "\$read2" \\
      "\$read1_bytes" "\$read2_bytes" "\$read1_md5" "\$read2_md5" \\
      >> '${meta.sample}.download.tsv'
    """
}

process FASTP {
    container params.container_image
    cpus params.threads
    maxForks params.max_forks
    publishDir "${params.outdir}/qc", mode: "copy", pattern: "*fastp.*"

    input:
    tuple val(meta), path(read1), path(read2), path(download_manifest)

    output:
    tuple val(meta),
          path("${meta.sample}_R1.trimmed.fastq.gz"),
          path("${meta.sample}_R2.trimmed.fastq.gz"),
          emit: trimmed
    path "${meta.sample}.fastp.html", emit: html
    path "${meta.sample}.fastp.json", emit: json

    script:
    """
    fastp \\
      --in1 ${read1} \\
      --in2 ${read2} \\
      --out1 ${meta.sample}_R1.trimmed.fastq.gz \\
      --out2 ${meta.sample}_R2.trimmed.fastq.gz \\
      --thread ${task.cpus} \\
      --html ${meta.sample}.fastp.html \\
      --json ${meta.sample}.fastp.json
    """
}

process SALMON_INDEX {
    container params.container_image
    cpus params.threads
    publishDir "${params.outdir}/reference", mode: "copy"

    output:
    path "salmon_index", emit: index
    path "tx2gene.tsv", emit: tx2gene
    path "transcripts.fa"
    path "annotation.gtf"

    script:
    """
    base='https://ftp.ensembl.org/pub/release-${params.ensembl_release}/fasta/homo_sapiens/cdna'
    annotation='https://ftp.ensembl.org/pub/release-${params.ensembl_release}/gtf/homo_sapiens'
    curl --retry 10 --retry-delay 10 --retry-max-time 600 -fsSL \\
      "\${base}/Homo_sapiens.GRCh38.cdna.all.fa.gz" -o transcripts.fa.gz
    curl --retry 10 --retry-delay 10 --retry-max-time 600 -fsSL \\
      "\${annotation}/Homo_sapiens.GRCh38.${params.ensembl_release}.gtf.gz" -o annotation.gtf.gz
    gunzip -f transcripts.fa.gz annotation.gtf.gz
    salmon index -t transcripts.fa -i salmon_index -k 31
    awk -F '\\t' '
      \$3 == "transcript" {
        gene = \$9
        transcript = \$9
        sub(/.*gene_id "/, "", gene)
        sub(/".*/, "", gene)
        sub(/.*transcript_id "/, "", transcript)
        sub(/".*/, "", transcript)
        if (gene != "" && transcript != "") print transcript "\\t" gene
      }
    ' annotation.gtf | sort -u > tx2gene.tsv
    test -s tx2gene.tsv
    """
}

process SALMON_QUANT {
    container params.container_image
    cpus params.threads
    maxForks params.max_forks
    publishDir "${params.outdir}/quant", mode: "copy", pattern: "*.quant.sf"

    input:
    tuple val(meta), path(read1), path(read2), path(salmon_index)

    output:
    tuple val(meta),
          path("${meta.sample}.quant.sf"),
          path("${meta.sample}_salmon"),
          emit: quant

    script:
    """
    salmon quant \\
      -i ${salmon_index} \\
      -l A \\
      -1 ${read1} \\
      -2 ${read2} \\
      --validateMappings \\
      --seqBias \\
      --gcBias \\
      -p ${task.cpus} \\
      -o quant
    cp quant/quant.sf ${meta.sample}.quant.sf
    mkdir -p ${meta.sample}_salmon/aux_info
    cp quant/aux_info/meta_info.json ${meta.sample}_salmon/aux_info/
    if [ -f quant/aux_info/lib_format_counts.json ]; then
      cp quant/aux_info/lib_format_counts.json ${meta.sample}_salmon/aux_info/
    fi
    if [ -f quant/aux_info/flenDist.txt ]; then
      cp quant/aux_info/flenDist.txt ${meta.sample}_salmon/aux_info/
    fi
    """
}

process MULTIQC {
    container params.multiqc_container_image
    publishDir "${params.outdir}/multiqc", mode: "copy"

    input:
    path fastp_reports
    path salmon_reports

    output:
    path "multiqc_report.html"
    path "multiqc_general_stats.txt"

    script:
    """
    mkdir -p multiqc_input
    cp -L *.fastp.json multiqc_input/
    printf '%s\\n' 'use_filename_as_sample_name:' '  - fastp' > multiqc_config.yaml
    mkdir -p multiqc_input/salmon
    for salmon_report in *_salmon; do
      sample=\${salmon_report%_salmon}
      mkdir -p "multiqc_input/salmon/\$sample"
      cp -LR "\$salmon_report/aux_info" "multiqc_input/salmon/\$sample/"
    done
    multiqc multiqc_input --config multiqc_config.yaml --outdir multiqc_output --filename multiqc_report.html --force
    cp multiqc_output/multiqc_report.html .
    cp multiqc_output/multiqc_report_data/multiqc_general_stats.txt .
    """
}

process SAMPLE_QC_SUMMARY {
    container params.container_image
    publishDir "${params.outdir}/results", mode: "copy"

    input:
    path fastp_reports
    path salmon_reports
    path samplesheet

    output:
    path "sample_qc_summary.tsv"
    path "sample_qc_plot.png"

    script:
    """
    Rscript ${projectDir}/analysis/rnaseq_sample_qc.R ${samplesheet}
    """
}

process DESEQ2 {
    container params.container_image
    publishDir "${params.outdir}/results", mode: "copy"

    input:
    tuple val(sample_meta), path(quant_files)
    path tx2gene
    path analysis_script

    output:
    path "deseq2_results.csv"
    path "analysis_summary.txt"
    path "ma_plot.png"
    path "volcano_plot.png"
    path "pca_plot.png"
    path "session_info.txt"
    path "normalized_counts.csv"
    path "gene_variance_diagnostics.csv"
    path "crispld2_paired_counts.png"
    script:
    def sample_manifest = (0..<sample_meta.size()).collect { index ->
        def meta = sample_meta[index]
        "${meta.sample}\t${meta.cell}\t${meta.dex}\t${quant_files[index]}"
    }.join("\n")
    """
    printf 'sample\\tcell\\tdex\\tquant_file\\n%s\\n' '${sample_manifest}' > quant_manifest.tsv
    Rscript ${analysis_script} quant_manifest.tsv ${tx2gene}
    """
}

workflow {
    if ((params.max_forks as Integer) < 1) {
        error "max_forks must be a positive integer."
    }
    if ((params.download_forks as Integer) < 1) {
        error "download_forks must be a positive integer."
    }
    def samplesheet = Channel.fromPath(params.samplesheet, checkIfExists: true)
    def salmon_samples = samplesheet
        .splitCsv(header: true, sep: '\t')
        .map { row ->
            tuple(
                [sample: row.sample, cell: row.cell, dex: row.dex],
                row.run
            )
        }

    DOWNLOAD_READS(salmon_samples)
    FASTP(DOWNLOAD_READS.out)
    SALMON_INDEX()
    salmon_index = SALMON_INDEX.out.index
    tx2gene = SALMON_INDEX.out.tx2gene
    SALMON_QUANT(FASTP.out.trimmed.combine(salmon_index))
    fastp_reports = FASTP.out.json.collect()
    salmon_reports = SALMON_QUANT.out.quant
        .map { meta, quant_file, salmon_report -> salmon_report }
        .collect()
    MULTIQC(fastp_reports, salmon_reports)
    SAMPLE_QC_SUMMARY(fastp_reports, salmon_reports, file(params.samplesheet))

    quant_results = SALMON_QUANT.out.quant
        .map { meta, quant_file, salmon_report -> tuple(meta, quant_file) }
        .collect(flat: false)
        .map { rows ->
            tuple(
                rows.collect { row -> row[0] },
                rows.collect { row -> row[1] }
            )
        }
    DESEQ2(
        quant_results,
        tx2gene,
        file("${projectDir}/analysis/rnaseq_airway_deseq2.R")
    )
}
