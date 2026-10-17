# SeqCheckFlow User Guide

This guide describes the project as it exists today: its supported entry
points, commands, generated files, runtime dependencies, and boundaries. The
project has one single-file QC path and several separate utilities and example
workflows; running one does not implicitly start the others.

## Reproducible command runner

For routine use, invoke the cross-platform Python launcher from any directory:

```text
python <project>/scripts/seqcheckflow.py <command> [options]
```

The launcher needs Python 3.10+ and Docker Compose. It builds or reuses the
`seqcheckflow` image from `containers/environment.yml`, mounts this project as
`/workspace`, and runs the selected module inside the container. It does not
install project packages on the host. Inputs and outputs must be inside the
project directory so the container can see them. Docker image and package
downloads require network access on the first build. The tool runtime is Linux;
Docker Desktop supplies it on Windows and macOS.

Run these commands at the project root (PowerShell uses backticks for line
continuation; bash uses backslashes):

| Command | What it does |
| --- | --- |
| `python scripts/seqcheckflow.py analyze <file> [options]` | Validate and summarize one FASTA, FASTQ, VCF/VCF.GZ, BAM, or CRAM; emit JSON and text reports. |
| `python scripts/seqcheckflow.py download <download-subcommand> ...` | Search/download NCBI sequence records, download SRA FASTQ, or fetch direct-URL VCF/BAM/CRAM files. |
| `python scripts/seqcheckflow.py prepare-hg002 [options]` | Download and prepare a regional HG002 benchmark dataset. |
| `python scripts/seqcheckflow.py benchmark [options]` | Run the direct-tool and SeqCheckFlow germline workflows on user-supplied data and compare calls with a supplied truth set. |
| `python scripts/seqcheckflow.py compare-hg002 [options]` | Backward-compatible alias for `benchmark`. |

The runner's `--build` behavior means a changed container definition is picked
up on the next command. Use `docker compose build seqcheckflow` to build it
without running a command. `docker compose run --rm seqcheckflow <command>` is
available when you want to call another Python module directly.

### Single-file QC examples

```bash
python scripts/seqcheckflow.py analyze data/examples/example.fasta
python scripts/seqcheckflow.py analyze data/examples/example.fastq --minimum-mean-quality 25
python scripts/seqcheckflow.py analyze data/variants/sample.vcf.gz --results-dir results/sample-vcf
python scripts/seqcheckflow.py analyze data/alignments/sample.cram --reference data/references/reference.fasta
```

Reports are written below `results/` by default. Specify `--results-dir` to
select another project-relative output directory. FASTQ quality is Phred+33;
the default threshold is mean read quality 20. BAM/CRAM analysis uses samtools;
CRAM decoding can use a matching reference FASTA. These checks and summaries do
not trim, align, call, annotate, or interpret variants.

### What a single-file report tells you

The `analyze` command first checks file structure, then reports measurements for
that file. The output is a JSON report plus a readable text summary; a valid
file is not automatically a biologically correct or scientifically interpreted
result.

| File | Checks and measurements | How to read it / limits |
| --- | --- | --- |
| FASTA (`.fa`, `.fasta`, `.fna`) | Checks record/header structure and sequence characters; reports record count, total bases, minimum/maximum/mean sequence length, and GC percentage. | Useful for checking sequence inventory and basic composition. GC is calculated across all sequence characters in the denominator; it does not identify the organism or verify an assembly. |
| FASTQ (`.fq`, `.fastq`) | Checks four-line records, sequence/quality length agreement, and characters; reports read count, length and base-quality distributions, mean quality, GC, ambiguous bases, and count/percentage below the selected mean-read-quality threshold. | Quality characters are interpreted as Phred+33. The default cutoff is mean read quality 20 per read. This command summarizes one file; it does not trim reads, test whether two mate files pair correctly, or prove coverage. |
| VCF / VCF.GZ | Checks required header and record structure, positive positions, allele fields, QUAL parsing, and genotype indices; reports record/contig counts, SNP/indel/other allele counts, filter categories, sample/genotype counts, and mean QUAL. | These are syntax and summary checks. The command does not compare REF alleles against a reference, evaluate against truth, annotate functional consequences, or classify pathogenicity. |
| BAM | Runs `samtools quickcheck`, `flagstat`, `stats`, and `coverage`; reports alignment, read/pair, mapping, and coverage summaries. | Integrity and mapping summaries do not call variants or establish that reads belong to the claimed sample. Review reference, mapping quality, and coverage for the region relevant to your question. |
| CRAM | Runs the same summaries; if `--reference` is supplied, decodes through a temporary BAM using that FASTA first. | CRAM decoding depends on the matching reference assembly and contigs. A successful decode does not establish biological identity or variant accuracy. |

For example, `low_quality_reads` counts reads whose **mean per-base** quality is
below the configured threshold; it is not the count of individual low-quality
bases. For CRAM, FASTQ, and VCF, keep the reference/build, quality encoding,
and sample metadata with the report so the values can be interpreted later.

### Download examples

```bash
python scripts/seqcheckflow.py download search "BRCA1[Gene] AND human[Organism]" --email researcher@example.org
python scripts/seqcheckflow.py download fastq SRR123456 --threads 4
python scripts/seqcheckflow.py download variants https://example.org/sample.vcf.gz
python scripts/seqcheckflow.py download alignment https://example.org/sample.cram
```

The sequence search/download subcommands use NCBI Entrez and require a valid
email; remote downloads require network access. SRA FASTQ conversion uses
`fasterq-dump` (SRA Toolkit 3.2.1 in the container). Direct VCF and alignment
downloads require accessible URLs. Download helpers are utilities and do not
automatically feed the files to the analysis command.

## Available analyses and tools

| Area | Current behavior | Main files / modules |
| --- | --- | --- |
| FASTA | Validates records; summarizes count, lengths, total bases, and GC content. | `seqcheckflow.validation`, `seqcheckflow.fasta` |
| FASTQ | Validates four-line records; summarizes read length, base composition, and quality distribution/threshold counts. | `seqcheckflow.validation`, `seqcheckflow.fastq`, `seqcheckflow.qc` |
| VCF / VCF.GZ | Validates and summarizes records, filters, genotypes, and QUAL values. | `seqcheckflow.variants` |
| BAM / CRAM | Uses samtools integrity checks and reports flagstat, stats, and coverage summaries. | `seqcheckflow.samtools` |
| Download | NCBI Entrez sequence search/download, SRA-to-FASTQ, and direct-URL VCF/BAM/CRAM downloads. | `seqcheckflow.download` |
| BLAST | Optional remote NCBI BLAST search, exposed as a Python helper; not a standalone CLI command. | `seqcheckflow.blast` |
| Alignment | Optional BWA/minimap2 alignment and SAM-to-BAM helper functions; not automatically part of single-file analysis. | `seqcheckflow.alignment` |
| RNA-seq | Eight-sample ENA → fastp → Salmon → MultiQC and tximport/DESeq2 example. | `main.nf`, `analysis/` |
| HG002 | Preparation code accepts GRCh38 autosomes chr1–chr22; wrapper-versus-direct-tool comparison; separate stage-by-stage Nextflow DAG. End-to-end results in this checkout cover chr20 and two chr21 intervals only. | `seqcheckflow.giab_data`, `seqcheckflow.full_benchmark`, `hg002.nf` |

The separate `seqcheckflow.cli` entry point prints a basic FASTA/FASTQ summary.
The documented `analyze` command is the report-producing interface and supports
all five formats above.

### Other project utilities: what their results mean

| Utility | Result | Interpretation limit |
| --- | --- | --- |
| NCBI search and download | Sequence records or downloaded FASTQ/VCF/BAM/CRAM files. SRA runs are converted to FASTQ; direct URLs are copied as files. | Retrieval is not analysis. Confirm accession, organism, sample, assembly, and file checksums before using a downloaded file. |
| Remote NCBI BLAST helper | One best-HSP summary per hit: accession/description, percent identity, query coverage, E-value, and bit score. | These values describe sequence similarity against the selected remote database. They do not prove gene function, orthology, pathogenicity, or that the best hit is biologically correct. |
| BWA/minimap2 alignment helpers | SAM alignment output and SAM-to-BAM conversion. | Alignment is a mapping step, not a variant call or accuracy result. Review mapping and coverage with an alignment QC workflow and a matching reference. |

## Reproduce the analysis examples

### RNA-seq workflow

Prerequisites are Java 17, Nextflow 24.10.5, Docker, and a Linux host or WSL2.
The pipeline image installs R 4.4.3, Bioconductor 3.20, fastp, Salmon, DESeq2,
and tximport. From the project root:

```bash
docker build -f containers/rnaseq.Dockerfile -t seqcheckflow-rnaseq:latest .
nextflow run main.nf -profile docker \
  --samplesheet analysis/airway_samples.tsv \
  --threads 2 --max_forks 1 --outdir results/rnaseq_airway
```

This downloads the eight public libraries and the Ensembl 112 GRCh38 cDNA
reference, so it requires internet access and substantial disk space. FASTQ
downloads stream to task-local partial files, resume after interrupted transfers,
retry transient failures, and verify ENA byte counts, MD5 checksums, and gzip
integrity before publishing each mate. Per-sample `*.download.tsv` manifests
record the source URLs, sizes, and checksums. Threads per fastp/Salmon task are
controlled by `--threads`; downloads run up to four at a time by default and
can be tuned with `--download_forks`. Concurrent fastp and Salmon tasks are
controlled by `--max_forks` (default 1). Outputs include trimmed-read QC, Salmon quantification, MultiQC,
DESeq2 result tables/plots, and a session-information file under the output
directory. A preview or synthetic R smoke test checks workflow/software wiring,
not the full biological analysis. Full workflow runs are manual in GitHub
Actions.

This is the complete eight-library dataset in the checked-in sample sheet, not
a subsample. To run it without a local Nextflow installation, use the GitHub
**Actions → SeqCheckFlow RNA-seq → Run workflow** page; choose the threads and
task-concurrency settings and download the `airway-raw-rnaseq-results` artifact
when it completes. Users without write access to the main repository can fork
it, enable Actions, and dispatch the workflow from their fork. The default
GitHub-hosted runner is intended for this RNA-seq example, not whole-genome
variant calling.

This command reproduces **SeqCheckFlow's reanalysis**, not the original paper's
exact computational pipeline. The paper used Taffeta, TopHat 2.0.4, Cufflinks
and Cuffdiff 2.0.2, hg19 RefSeq plus ERCC references, and related legacy QC
tools; this project uses fastp, Salmon, tximport, DESeq2, and Ensembl 112
GRCh38. The [analysis report](../PIPELINE_ANALYSIS.md#primary-sources-and-what-this-project-can-conclude)
lists the original tool versions and what would be needed for a closer
computational recreation. The paper also includes wet-lab and genetic analyses
that this workflow does not reproduce.

### AWS Batch execution (optional)

Both Nextflow workflows have an `awsbatch` profile. This profile sends tasks to
an existing AWS Batch job queue, uses S3 for the Nextflow work directory, and
publishes deliverables to the S3 `--outdir`. It does not create the AWS
infrastructure. Follow the [Nextflow AWS Batch setup
guide](https://www.nextflow.io/docs/24.10/aws.html#aws-batch) and the [AWS Batch
getting started guide](https://docs.aws.amazon.com/batch/latest/userguide/getting-started.html)
to provide a queue/compute environment, an S3 bucket, IAM permissions, and
network access for image pulls and public data downloads. Keep the bucket and
compute environment in the same AWS region. The profile defaults to `us-east-1`;
override it with `--aws_region` for another region. Use an EC2-backed Batch compute
environment for these Docker container workflows.

The launch machine needs Java 17, Nextflow 24.10.5, AWS credentials for the
driver, and Docker to build/push images. Install the compatible AWS plugin with
the versioned `-plugins nf-amazon@2.9.2` launch option. Build the workflow
images for the Linux architecture used by the Batch compute environment, push
them to ECR, and pass the full ECR image URI. Do not put AWS keys in this
repository. The Batch job role and instance roles must grant the required S3,
ECR, CloudWatch Logs, and Batch access; use least-privilege policies. The
HG002 preparation stage also needs outbound access to the public GIAB, UCSC,
and Broad sources. Nextflow uses the AWS CLI to stage S3 files: the Batch
compute environment AMI must provide it at `/home/ec2-user/miniconda/bin/aws`
(the profile's default), or pass its actual host path using `--aws_cli_path`.
Use a custom ECS-optimized AMI if needed to install the AWS CLI at that path;
see [Nextflow's AWS CLI/AMI notes](https://docs.seqera.io/nextflow/aws#custom-ami).
Choose an EC2 instance/storage configuration with enough memory and task-local
disk for reference indexes and intermediate BAM/FASTQ files; the small default
Batch instance disk may be insufficient for genomic workflows.

#### AWS Batch minimum and recommended starting setups

These are **candidate configurations for a first run**, not validated project
minimums. The AWS Batch profile has not been exercised in an AWS account. EC2
memory shown below is instance capacity; Batch also reserves host resources, so
the container must request less than the instance's total memory. Instance
types must be available in your selected region. See AWS's [EC2 instance
specifications](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-types.html)
and [Batch compute environment guidance](https://docs.aws.amazon.com/batch/latest/userguide/create-compute-environment.html).

| Workload | Candidate minimum Batch setup | Recommended starting setup | Nextflow task memory |
| --- | --- | --- | --- |
| RNA-seq or ~1 Mb HG002 region | EC2 `m7i.xlarge` class (4 vCPU, 16 GiB); 100 GB encrypted gp3 EBS; Batch `minvCpus=0`, `maxvCpus=4` | `m7i.2xlarge` class (8 vCPU, 32 GiB); 200 GB encrypted gp3 EBS; allow up to 8 vCPUs | Keep the current 8 GB default. On the smaller setup, start with `--download_forks 1 --max_forks 1`. |
| Full HG002 chromosome, one at a time | EC2 `r7i.4xlarge` class (16 vCPU, 128 GiB); 500 GB encrypted gp3 EBS; Batch `minvCpus=0`, `maxvCpus=16` | `r7i.8xlarge` class (32 vCPU, 256 GiB); 1 TB encrypted gp3 EBS; allow up to 32 vCPUs | Pass `--aws_batch_memory '64 GB'` and `--threads 8`. The 64 GB request is the workflow's per-task memory setting; select an instance with headroom above it. |

The EC2 families above are examples: AWS lists `m7i.xlarge` at 4 vCPUs/16
GiB and `m7i.2xlarge` at 8/32, while `r7i.4xlarge` is 16/128 and
`r7i.8xlarge` is 32/256. Confirm regional availability and current prices
before choosing. [AWS Batch launch templates](https://docs.aws.amazon.com/batch/latest/userguide/launch-templates.html)
can increase the encrypted EBS data volume; the sizes in this table are
starting allocations, not measured per-run disk consumption. S3 is the durable
Nextflow work/results store, but tasks still need local scratch while running.

For an initial setup, use a managed **EC2** compute environment, an existing
VPC with outbound access to Batch/ECS, ECR, S3, CloudWatch Logs, and the public
ENA/Ensembl/GIAB/UCSC/Broad endpoints required by the selected workflow; create
a job queue attached to that environment; and use one same-region S3 bucket
for `--work-dir` and results. Set the environment's minimum and desired vCPUs
to zero so it can scale down when idle, and bound `maxvCpus` to the table's
starting capacity. Follow AWS's [managed EC2 Batch setup
guide](https://docs.aws.amazon.com/batch/latest/userguide/create-compute-environment-managed-ec2.html)
and [launch template guide](https://docs.aws.amazon.com/batch/latest/userguide/launch-templates.html)
to configure encrypted, adequately sized EBS. The driver needs Java,
Nextflow, the `nf-amazon` plugin, AWS credentials, and the versioned images in
ECR. The Batch compute instances need the instance profile, outbound network,
and AWS CLI path described above. Keep credentials out of the repository; use
scoped IAM roles and limit S3 access to the workflow prefixes.

Start with On-Demand capacity and one workload. After collecting the Nextflow
trace, job logs, and free-disk measurements, adjust the task memory, EBS size,
and `maxvCpus`. Set an AWS Budget alert and use the [AWS Pricing
Calculator](https://calculator.aws/) for the chosen region, instance hours,
EBS, ECR, S3, and data transfer. A budget alert is a notification, not a hard
spending cap. Avoid leaving nonzero desired capacity running after the analysis.

For example, after creating ECR repositories and configuring AWS credentials,
build and push versioned images from the repository root (replace the account,
region, and tag):

```bash
export AWS_REGION=us-east-1
export ECR_REGISTRY=123456789012.dkr.ecr.${AWS_REGION}.amazonaws.com
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker build --platform linux/amd64 -f containers/rnaseq.Dockerfile \
  -t "$ECR_REGISTRY/seqcheckflow-rnaseq:project-v1" .
docker push "$ECR_REGISTRY/seqcheckflow-rnaseq:project-v1"
docker build --platform linux/amd64 -f containers/Dockerfile \
  -t "$ECR_REGISTRY/seqcheckflow:project-v1" .
docker push "$ECR_REGISTRY/seqcheckflow:project-v1"
```

Mirror the pinned MultiQC image to an ECR repository as well if Batch workers
cannot pull from Docker Hub. Use the resulting ECR URI for
`--multiqc_container_image`.

Example RNA-seq launch (replace the bucket, queue, region, account ID, and
versioned ECR image URIs with resources already configured for your AWS
account):

```bash
nextflow run main.nf \
  -plugins nf-amazon@2.9.2 \
  -profile awsbatch \
  -work-dir s3://YOUR_BUCKET/seqcheckflow-work/rnaseq \
  --aws_queue YOUR_BATCH_QUEUE \
  --aws_region us-east-1 \
  --aws_cli_path /home/ec2-user/miniconda/bin/aws \
  --container_image 123456789012.dkr.ecr.us-east-1.amazonaws.com/seqcheckflow-rnaseq:VERSION \
  --multiqc_container_image 123456789012.dkr.ecr.us-east-1.amazonaws.com/seqcheckflow-multiqc:VERSION \
  --samplesheet analysis/airway_samples.tsv \
  --threads 2 --max_forks 1 \
  --outdir s3://YOUR_BUCKET/seqcheckflow-results/rnaseq
```

Example HG002 Nextflow launch (omit `--prepared_dir` to prepare the selected
interval in the workflow, or supply a directory that the launch host can
stage):

```bash
nextflow run hg002.nf \
  -plugins nf-amazon@2.9.2 \
  -profile awsbatch \
  -work-dir s3://YOUR_BUCKET/seqcheckflow-work/hg002 \
  --aws_queue YOUR_BATCH_QUEUE \
  --aws_region us-east-1 \
  --aws_cli_path /home/ec2-user/miniconda/bin/aws \
  --container_image 123456789012.dkr.ecr.us-east-1.amazonaws.com/seqcheckflow:VERSION \
  --interval chr21:20000000-21000000 --threads 2 \
  --outdir s3://YOUR_BUCKET/seqcheckflow-results/hg002
```

For a full-chromosome AWS Batch run, use a compute environment with enough
memory and task-local disk for the whole interval, and increase the per-task
memory request to match that environment. For example, replace the interval,
thread, and output options in the HG002 launch above with:

```bash
  --interval chr21:1-46709983 --threads 8 \
  --aws_batch_memory '64 GB' \
  --outdir s3://YOUR_BUCKET/seqcheckflow-results/hg002_chr21_full
```

Keep the other launch options. AWS Batch must place a job requesting that
memory on an instance that can satisfy it. Tune task-local storage too;
increasing memory alone does not provision either resource.

The HG002 Nextflow workflow accepts one GRCh38 autosomal interval per run. For
a whole-chromosome chr21 run, the interval is `chr21:1-46709983`. On a high-
memory Linux/WSL2 machine, build the image and run:

```bash
docker build -f containers/Dockerfile -t seqcheckflow:latest .
nextflow run hg002.nf -profile docker \
  --interval chr21:1-46709983 --threads 8 \
  --outdir results/HG002_chr21_full
```

This example runs the complete chr21 interval through the existing preparation,
alignment, BQSR, calling, and truth-scoring stages. The current workflow does
not scatter a chromosome into smaller calling jobs or run all 22 autosomes in
one invocation. To run all autosomes, use one full-contig interval per run; get
each `chrN` length from the [UCSC hg38 chromosome sizes
file](https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.chrom.sizes)
and set the interval to `chrN:1-LENGTH`. Run chromosomes sequentially and use a
unique output path for each. Whole chromosomes need substantially more scratch
space, memory, and time than the documented 1 Mb pilots. The default GitHub
runner is not a suitable whole-chromosome compute target.

For AWS Batch, the `awsbatch` profile defaults to 8 GB per task. Set
`--aws_batch_memory '64 GB'` (or the size supported by your configured compute
environment) for whole-chromosome tasks. This memory setting does not create or
resize Batch resources; configure the queue's EC2 instances and task-local disk
to match the workload. The Batch profile has not been validated in a live AWS
account.

The S3 work prefix stores task intermediates and can become large; the result
prefix contains published outputs. Set an S3 lifecycle policy appropriate for
your retention needs after confirming which outputs you want to keep. AWS
Batch, EC2 compute, ECR, S3 requests/storage, and data transfer may incur
charges. No cloud run is performed by this documentation or CI. The AWS
profile is configuration support only until exercised in an account with the
required infrastructure and permissions.

## Machine requirements by analysis

The table gives practical planning targets for a Linux host or WSL2 with Docker
and Nextflow. Disk values mean free space available to the run, separate from
the operating system. RNA-seq and whole-chromosome figures are conservative
starting estimates, not measured minimums: the full RNA-seq run has not been
profiled for peak resource use here, and whole-chromosome HG002 runs have not
been validated end to end. Actual needs depend on read depth, concurrent tasks,
filesystem overhead, and retained Nextflow work files.

| Analysis | Practical starting point | Recommended machine | Notes |
| --- | --- | --- | --- |
| Single-file CLI on small FASTA/FASTQ/VCF examples | 2 CPU cores, 4 GB RAM; free disk at least 2× the input for temporary outputs | 4 cores, 8 GB RAM; extra disk for reports or converted files | BAM/CRAM work can use more disk and time; samtools must be installed for alignment summaries. |
| Full eight-library RNA-seq (`main.nf`) | 4 cores, 16 GB RAM, 100 GB free disk | 8 cores, 32 GB RAM, 200 GB free disk | Internet required. Keep `--max_forks 1` and `--download_forks 2` on the smaller machine. Raw/trimmed reads and task intermediates make storage the main constraint. RAM and disk values are estimates pending a profiled full run. |
| HG002 regional run (about 1 Mb) | 4 cores, 8 GB RAM, 30 GB free disk | 8 cores, 16 GB RAM, 60 GB free disk | Retained chr21 runs measured about 0.6 GiB peak sampled process-tree RSS and took about 19 minutes for the low-coverage interval. These are one-machine observations, not minimums or guarantees. |
| HG002 whole chromosome | Start with 8 cores, 64 GB RAM, 200 GB task-local scratch | 16 cores, 128 GB RAM, 500 GB task-local scratch | Unvalidated planning estimates only. Run one chromosome at a time, inspect Nextflow trace and disk use, then adjust. AWS Batch must provide the requested memory and enough task-local scratch. |

The full RNA-seq GitHub Actions job currently uses `ubuntu-latest`. GitHub lists
standard `ubuntu-latest` public-repository runners as 4 CPUs, 16 GB RAM, and
14 GB SSD; that runner's disk is below the local RNA-seq starting target, so a
full run may run out of space even if CPU and RAM are adequate. Check the
[current GitHub-hosted runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
before relying on it. Use a local machine with adequate free disk or configured
cloud compute for large runs. GitHub Actions validation/smoke jobs are much
smaller than the full analyses.

For reproducible sizing, record the host, free disk before and after, thread
and concurrency settings, runtime, and Nextflow trace for each full run. Treat
the first completed full run as a sizing baseline; the estimates above are not
validated minimum requirements.

### RNA-seq workflow: stages, outputs, and interpretation

The sample sheet has eight paired libraries: four airway smooth-muscle donor
cell lines, each with untreated (`untrt`) and dexamethasone-treated (`trt`)
reads. The workflow uses the same donor label for each treatment pair.

| Stage | What it does | Main output and check |
| --- | --- | --- |
| Download | Resolves each ENA run accession to paired FASTQ URLs, streams both mates to resumable partial files, and retries interrupted transfers. | Published `raw/` FASTQs and per-sample download manifests; byte count, ENA MD5, and gzip integrity are checked before publication. Keep the run accession-to-sample mapping from `analysis/airway_samples.tsv`. |
| fastp | Trims adapters and low-quality sequence from paired reads and generates per-sample QC. | Trimmed FASTQs and HTML/JSON under `qc/`, plus `results/sample_qc_summary.tsv` with Q30 before/after filtering, retained reads, and Salmon mapping rates. |
| Salmon reference setup | Downloads Ensembl 112 GRCh38 cDNA transcripts and matching GTF, builds the transcript index, and creates a transcript-to-gene map. | Persistent `reference/` outputs include the index, transcript FASTA, annotation, and `tx2gene.tsv`; the FASTA and annotation must be from the same release/build. |
| Salmon quantification | Uses selective alignment with mapping validation plus sequence- and GC-bias correction to estimate transcript abundance for each library. | `quant/*.quant.sf` and auxiliary metadata; inspect mapping rates and library summaries. Quantification is not a genome variant call or gene-level significance test. |
| MultiQC | Combines fastp JSON and Salmon auxiliary summaries across samples. | `multiqc/multiqc_report.html` and general statistics; this is a workflow/read/quantification QC report, not evidence of a treatment effect. |
| tximport and DESeq2 | Aggregates transcript estimates to genes with the matching transcript map, removes genes with total counts below 10, and fits `~ cell + dex`; `untrt` is the reference level. | `results/deseq2_results.csv`, `results/normalized_counts.csv`, `results/gene_variance_diagnostics.csv`, summary, and `session_info.txt`; the diagnostics include normalized-count variance and fitted dispersion alongside effect estimate and standard error. |
| Plots | Produces a PCA, MA plot, and volcano plot from the DESeq2 fit. | Interpret the PCA as exploratory sample structure; use MA for effect versus abundance; use the volcano plot for effect size versus adjusted evidence. None replaces the model or multiple-testing threshold. |

For this run, the PCA’s first two components account for 52% and 37% of the
variance. Mapping rates were 92.3–93.9%. No genes met BH-adjusted `p < 0.05` for
the dexamethasone coefficient. This means the analysis did not detect
significant genes with four donors under this model; it does not show that the
treatment has no biological effect. Large estimated fold changes without small
adjusted p-values are uncertain estimates, not significant discoveries.

Before interpreting another RNA-seq result, establish that sample IDs,
accessions, donor pairing, and treatment labels agree; read QC and quantification
are acceptable; the transcript reference and gene annotation match; the model
represents the experimental design; and the biological replicate count supports
the intended inference. Keep the samplesheet, reference release, exact
parameters, pipeline/container versions, MultiQC, DESeq2 table, and R session
information together. The saved normalized counts and variance/dispersion table
make it possible to inspect genes whose expression varies strongly across
samples. The [analysis report](../PIPELINE_ANALYSIS.md) explains why each plot
was selected and what its observed pattern means.

### HG002 regional benchmark

The short Docker Compose launcher commands prepare inputs and compare both
workflows. The HG002 preparation code accepts GRCh38 autosomes chr1–chr22;
however, only chr20 and chr21 intervals have end-to-end benchmark evidence in
this checkout. Acceptance by the downloader does not mean every chromosome has
been validated. Preparation refuses to overwrite an existing directory, as
does comparison.
For a 1 Mb chr21 run in PowerShell:

```powershell
$prepared = "data/benchmark/giab_hg002_chr21_10000000_11000000"
python scripts/seqcheckflow.py prepare-hg002 `
  --interval chr21:10000000-11000000 --threads 2 --output-dir $prepared

$outdir = "results/HG002_chr21_comparison"
python scripts/seqcheckflow.py benchmark `
  --read1 "$prepared/HG002_R1.fastq" `
  --read2 "$prepared/HG002_R2.fastq" `
  --reference-fasta "$prepared/chr21.fa" `
  --known-sites-vcf "$prepared/Mills.hg38.region.vcf.gz" `
  --reference-sdf "$prepared/chr21.sdf" `
  --truth-vcf "$prepared/HG002.truth.region.vcf.gz" `
  --confident-regions "$prepared/HG002_chr21_10000000_11000000.confident.bed" `
  --interval chr21:10000000-11000000 --sample-name HG002 --threads 2 --output-dir $outdir
```

Input preparation queries public GIAB resources for a genomic region. The
comparison runs BWA, samtools, GATK, bcftools, and RTG Tools in
the pinned container and writes baseline/candidate outputs, stage manifests,
truth-evaluation reports, and `comparison.json`. Disk/network requirements are
substantial. A separate stage-by-stage Nextflow DAG is run with
`nextflow run hg002.nf -profile docker`; it produces pipeline stages and truth
scores, but not the wrapper-versus-direct comparison table.

### What each benchmark stage does

| Stage | Purpose | What to establish or inspect |
| --- | --- | --- |
| Prepare HG002 region | Extract paired reads from the public indexed BAM and fetch the matching regional reference, known-sites VCF, GIAB truth VCF, confident-region BED, and RTG SDF. Read extraction includes 5-kb flanks and name-collates the regional BAM so mates stay paired. | Check `dataset.json` for the requested interval, resource paths, confident interval count, and input SHA-256 hashes. Preparation refuses to overwrite an existing directory. |
| Reference setup | Copy the reference into each workflow output and create BWA indexes, a samtools `.fai`, and a GATK sequence dictionary. | Ensure FASTA, indexes, dictionary, and RTG SDF all derive from the same assembly and sequence. Contig names must match all inputs. |
| FASTQ QC | Validate FASTQ structure and summarize read length and quality. | Confirm both mates are valid, correspond to the same sample, and have plausible read counts and quality. This summary does not prove adequate coverage at every locus. |
| BWA-MEM alignment | Map paired reads to the reference and add a read group with sample/platform metadata. | Check alignment summaries, mapped fraction, coverage, and mapping quality, especially at discordant loci. |
| SAM/BAM processing | Convert SAM to BAM, name-sort pairs, run `samtools fixmate`, coordinate-sort, mark duplicates, and index the duplicate-marked BAM. | Sorting order is required by downstream tools; fixmate prepares mate fields for duplicate marking. Duplicates are marked, not removed. Inspect stage logs and alignment QC. |
| BQSR | GATK `BaseRecalibrator` models systematic base-quality error using the supplied known-sites VCF; `ApplyBQSR` applies those recalibration estimates. | Known-sites is a calibration resource, not the truth set. Confirm that it matches the reference and that both paired workflows use the same file and interval. |
| Variant calling | GATK HaplotypeCaller examines the requested interval on the recalibrated BAM and emits a small-variant VCF. | Validate the VCF and inspect its sample, contig, coordinate range, and counts. This workflow does not establish clinical validity. |
| Truth evaluation | RTG `vcfeval` compares each callset with the GIAB truth VCF, restricted to the supplied confident BED. | Report BED-covered bases, scored truth variants, scored calls, TP/FP/FN, precision, recall, and F1. Calls outside the BED are unscored, not false positives. |

### Checks before interpreting a benchmark

1. Confirm that reads, reference FASTA/SDF, known-sites, truth VCF, BED, and
   interval refer to the same sample, assembly, and contig naming. In the
   generic command, the user supplies these resources; the CLI does not prove
   that the biological sample or assembly is correct.
2. Preserve the `dataset.json`, comparison JSON, workflow JSON files, tool
   versions, checksums, logs, and output VCFs. Use a new output directory for
   every run; the runner intentionally refuses to overwrite existing results.
3. Check the confident-region BED overlap and truth/call denominators before
   reading the score. The command-line interval is 1-based inclusive; BED
   coordinates are 0-based half-open.
4. Treat exact baseline/wrapper VCF parity as a wrapper check. Treat RTG metrics
   as accuracy evidence only for truth-scored bases. Compare several
   well-covered regions, aggregate TP/FP/FN counts, separate SNVs and indels,
   and inspect representative discordant loci for read depth, mapping quality,
   read support, and local sequence context.
5. Repeat runs under controlled conditions before making performance claims;
   a single wall-time or sampled-memory value is descriptive only.

For this project’s observed regional examples and the reason the chr21 scores
differ, see the [analysis report](../PIPELINE_ANALYSIS.md). The recommended
error review follows [GA4GH benchmarking best practices](https://pmc.ncbi.nlm.nih.gov/articles/PMC6699627/); see also [NIST's guidance on small targeted truth subsets](https://www.nist.gov/programs-projects/faqs-genome-bottle).

### Other organisms and user-supplied regions

The generic `benchmark` command is not hard-coded to HG002 or human chromosome
names; it is designed to accept supplied compatible resources. This code path
has not been demonstrated on another species in the retained project results.
Supply paired FASTQs, a reference FASTA, a matching known-sites VCF, an
RTG reference SDF made from that FASTA, a truth VCF, and a confident-regions
BED. The reference, VCFs, BED, reads, and `--interval` must use compatible
assemblies and matching contig names. For example, the same code can benchmark
a species whose reference uses `scaffold_21`:

```bash
docker compose run --build --rm seqcheckflow rtg format \
  -o data/custom/reference.sdf data/custom/reference.fa

python scripts/seqcheckflow.py benchmark \
  --read1 data/custom/sample_R1.fastq \
  --read2 data/custom/sample_R2.fastq \
  --reference-fasta data/custom/reference.fa \
  --known-sites-vcf data/custom/known_sites.vcf.gz \
  --reference-sdf data/custom/reference.sdf \
  --truth-vcf data/custom/truth.vcf.gz \
  --confident-regions data/custom/confident_regions.bed \
  --interval scaffold_21:100000-200000 \
  --sample-name sample_1 --threads 2 \
  --output-dir results/custom_species_region
```

The `contig:start-end` interval uses 1-based inclusive coordinates, as required
by GATK and samtools region arguments. BED confident-region files use the BED
0-based, half-open convention.

The generic benchmark does not fetch arbitrary species data or choose truth
sets for users; those resources need to be supplied and validated for the
species and assembly. A truth VCF and confident BED are required for accuracy
scores. The automated downloader remains a convenience recipe specifically
for HG002 GRCh38 autosomes chr1–chr22.

## Runtime and dependency reference

| Use | Host requirements | Container or optional dependencies |
| --- | --- | --- |
| Recommended launcher / core analyses | Python 3.10+, Docker with Compose, network for first image build | Python 3.12, Biopython 1.88, psutil 6.1.1, BWA 0.7.17, samtools/bcftools 1.20, GATK 4.5.0.0, RTG Tools 3.12.1, SRA Toolkit 3.2.1 |
| Direct local Python development | Python 3.10+ and `pip install -r requirements.txt`; Biopython and psutil are pinned | BAM/CRAM needs samtools on `PATH`; additional utilities need their respective external tools |
| RNA-seq / Nextflow examples | Java 17, Nextflow 24.10.5, Docker, Linux/WSL2 | R 4.4.3, Bioconductor 3.20, fastp, Salmon, DESeq2, tximport |
| Remote NCBI utilities | Internet; valid Entrez email for Entrez queries | BLAST executes on NCBI's remote service; no local BLAST database is packaged |

The conda environment pins the core command-line tool versions, and the Docker
base image is version-tagged. Package repositories and remote databases may
change or become unavailable; the container is not a byte-for-byte lockfile
for every transitive package. For strict archival reproduction, record the
container image digest and preserve input checksums, parameters, workflow
revision, reference assembly, and remote resource versions. Runtime and memory
measurements depend on host hardware and load.

## Data, outputs, and Git

- `data/examples/` contains the small FASTA/FASTQ demonstration inputs.
- Put original local files in `data/raw/`; generated/prepared inputs belong in
  `data/processed/` or `data/benchmark/` as appropriate. Large-data paths are
  ignored by Git.
- Single-file reports go to `results/` unless `--results-dir` is specified.
- Workflow results go to their `--outdir`. Nextflow also creates `work/` and
  `.nextflow/` execution state; these are ignored by Git.
- `analysis/airway_samples.tsv` describes sample accessions and design;
  `analysis/rnaseq_airway_deseq2.R` performs the gene-level analysis.
- `docs/reports/airway-multiqc.html` and `docs/images/` contain checked-in
  example outputs. `PIPELINE_ANALYSIS.md` explains the example findings and
  limitations.
- Never commit private or sensitive sample data. Review downloaded files
  before staging because some default download locations are not ignored.

## Tests and scope boundaries

GitHub Actions runs unit tests, CLI smoke checks, RNA-seq container/R smoke
checks, and a Nextflow preview on pushes and pull requests. Full RNA-seq runs
are manually dispatched; HG002 Nextflow runs are manually dispatched. CI
success therefore does not mean those large analyses were run.

These workflows are educational/research examples. The HG002 result is a
single-sample regional pilot, not whole-genome or clinical validation. The
RNA-seq analysis is a reanalysis of one eight-library public study, not
independent biological validation. See [ARCHITECTURE.md](../ARCHITECTURE.md),
[DESIGN_NOTES.md](../DESIGN_NOTES.md), and
[PIPELINE_ANALYSIS.md](../PIPELINE_ANALYSIS.md) for system design, metric
interpretation, and example results.
