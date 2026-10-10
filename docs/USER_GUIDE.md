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
| HG002 | Regional GIAB preparation for GRCh38 autosomes chr1–chr22; wrapper-versus-direct-tool comparison; separate stage-by-stage Nextflow DAG. | `seqcheckflow.giab_data`, `seqcheckflow.full_benchmark`, `hg002.nf` |

The separate `seqcheckflow.cli` entry point prints a basic FASTA/FASTQ summary.
The documented `analyze` command is the report-producing interface and supports
all five formats above.

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
reference, so it requires internet access and substantial disk space. Threads
per fastp/Salmon task are controlled by `--threads`; maximum concurrent
download, trimming, and quantification tasks are controlled by `--max_forks`
(default 1). Outputs include trimmed-read QC, Salmon quantification, MultiQC,
DESeq2 result tables/plots, and a session-information file under the output
directory. A preview or synthetic R smoke test checks workflow/software wiring,
not the full biological analysis. Full workflow runs are manual in GitHub
Actions.

### HG002 regional benchmark

The short Docker Compose launcher commands prepare inputs and compare both
workflows. The automatic HG002 downloader supports GRCh38 autosomes chr1–chr22;
preparation refuses to overwrite an existing directory, as does comparison.
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

### Other organisms and user-supplied regions

The generic `benchmark` command is not tied to HG002 or human chromosome
names. Supply paired FASTQs, a reference FASTA, a matching known-sites VCF, an
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
