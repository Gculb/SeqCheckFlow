# SeqCheckFlow Design Notes

This guide answers the biological and software questions that inform the
current implementation. For component boundaries and data flow, see
[ARCHITECTURE.md](./ARCHITECTURE.md).

## Biological questions

### FASTA

**What kind of biological data is stored in FASTA?**
FASTA stores biological sequences, commonly DNA, RNA, or protein sequences.
Each record starts with a `>` header followed by sequence text.

**What does each sequence represent?**
A record can represent anything from a short read or gene to a transcript,
contig, chromosome, or protein. Its header supplies an identifier and may
include descriptive metadata; the sequence itself does not tell us which
interpretation is correct.

**What can sequence length tell us?**
Length can help check whether a record is plausible for its intended purpose,
compare records, or summarize an assembly. It does not by itself identify a
sequence or establish biological function.

**What can GC content tell us?**
GC content is the fraction of sequence bases that are G or C. It can describe
base composition and help flag unusual regions or technical biases, but it is
not proof of an organism, gene, or function. Interpret it with the sequence
type, organism, and region in mind.

### FASTQ

**Why does FASTQ contain both sequence and quality information?**
The sequence records the called bases; the quality string records the
sequencer's confidence in each corresponding base. Keeping both lets analysis
account for likely sequencing errors rather than treating every base call as
equally certain.

**What does a Phred quality score represent?**
Phred score `Q` is `-10 log10(p)`, where `p` is the estimated probability that
the base call is wrong. For example, Q20 corresponds to an estimated 1% error
probability and Q30 to 0.1%. This is an error-probability scale, not a guarantee
that an individual base is correct.

**Why should low-quality reads potentially be filtered?**
Low-quality reads or bases can introduce false alignments and variant calls.
Filtering or trimming can reduce those errors, but removes data and may bias
coverage, so thresholds should be chosen and recorded for the experiment.
SeqCheckFlow's FASTQ QC currently reports read-quality metrics and the count below a
mean-quality threshold; it does **not** filter or trim reads.

### BLAST

**What biological question does BLAST answer?**
BLAST searches a selected sequence database for local sequence regions similar
to a query. It can identify candidate homologs or related sequences for
follow-up; it does not directly determine biological function.

**What is percent identity?**
The percentage of aligned positions in a selected alignment segment that have
the same residue or nucleotide. It depends on the alignment and is not the
same as similarity, which can also account for conservative amino-acid
substitutions.

**What is query coverage?**
The fraction of the query sequence spanned by the reported alignment. A
high-identity hit covering a small part of the query may be less informative
than a substantial alignment, so identity and coverage should be considered
together.

**What is an E-value?**
The expected number of matches with a score at least this good that could
occur by chance in a database search of the given size. Lower values are
stronger evidence against a random match under the search model; an E-value is
not the probability that a biological hypothesis is true.

**Why is similarity not necessarily proof of function?**
Similar sequences can share ancestry without retaining the same function;
short or low-complexity matches can be misleading; and function depends on
context, structure, expression, and experimental evidence. BLAST results are
candidate evidence that needs independent validation.

### Alignment

**What is the reference sequence?**
A reference is a chosen coordinate-bearing sequence assembly or sequence set
against which reads are compared. Assembly/version and contig naming matter:
the reference must be appropriate for the sample and downstream resources.

**What does it mean for a read to map?**
An aligner found a plausible placement of the read on the reference, allowing
for mismatches and sometimes gaps. Mapping is a computational match, not proof
that the placement is biologically correct; mapping quality estimates
placement confidence.

**What information is represented by SAM/BAM?**
SAM is a text alignment format and BAM is its compressed binary counterpart.
They can record read names, flags, reference and position, mapping quality,
CIGAR alignment operations, mate information, sequence, base qualities, and
optional tags such as read groups. BAM is generally more compact and faster
for programmatic access.

### samtools

**Why would we sort a BAM?**
Coordinate sorting orders alignments by reference and position, which is
required by many tools and makes index-based regional access possible.
Name-sorting instead groups alignments by read name, useful for operations
such as pairing reads or running `samtools fixmate`. The correct order depends
on the next tool.

**Why would we index a BAM?**
An index maps genomic regions to file blocks so tools can retrieve alignments
from a region without scanning the entire file. Coordinate sorting is normally
required first.

**What does mapping rate tell us?**
It is the fraction of reads that the aligner reports as mapped under the
chosen filters and reference. It can help detect poor read quality, an
inappropriate reference, contamination, or sample/library issues, but a high
rate does not guarantee correct placements or variant calls.

**What does coverage tell us?**
Depth is the number of reads covering a position; breadth is the fraction of
positions covered to a chosen depth. Average depth can conceal uncovered
regions, unevenness, duplicates, and low-quality alignments. Coverage supports
assessment of callability, but does not alone establish that a variant call is
correct. The benchmark reports mean depth and the fraction of requested-region
bases with at least one aligned base.

## Workflow tools and techniques

These tools belong to different analysis paths. They are not all chained
together, and BLAST is not part of either the RNA-seq or HG002 benchmark run.

### Why the RNA-seq workflow uses a different design

The RNA-seq example starts with eight paired-end airway smooth-muscle libraries
from GEO GSE52778. Its goal is to estimate gene expression and compare
dexamethasone-treated with untreated samples while accounting for donor cell
line. Its stages are:

1. **ENA and `curl`** retrieve paired FASTQ files for the run accessions in
   `analysis/airway_samples.tsv`. Data acquisition is an explicit workflow
   task; it still depends on the remote archive and network access.
2. **fastp** trims and filters reads and writes per-sample HTML and JSON QC
   reports. This is a preprocessing step in `main.nf`; the separate single-file
   CLI only reports FASTQ quality and does not trim reads.
3. **Salmon** builds a transcript index from Ensembl release 112 and quantifies
   each library with mapping validation and sequence- and GC-bias correction.
   It estimates transcript abundance without creating the coordinate-sorted
   BAM required by the variant-calling workflow.
4. **tximport** imports Salmon estimates and summarizes transcript-level
   abundance for gene-level analysis using the generated transcript-to-gene
   map.
5. **DESeq2** fits `~ cell + dex`, using donor cell line (`cell`) as a blocking
   factor and testing treated versus untreated (`dex`). It applies a low-count
   filter and reports Benjamini-Hochberg adjusted p-values. With four donors,
   no significant genes is not proof of no treatment effect.
6. **MultiQC** combines fastp reports and Salmon summary metadata into a
   project-level QC report.

Nextflow allows independent per-sample download, trimming, and quantification
tasks to run separately, then gathers all quantifications for one combined
DESeq2 analysis. This fan-out/fan-in pattern fits the data: sample processing
is independent, but the statistical model needs samples together. The custom
RNA-seq image contains R, fastp, Salmon, tximport, and DESeq2; MultiQC runs in
its own pinned image. This is a modern reanalysis of public reads, not a
recreation of the original study's legacy computational or experimental
methods.

### Why the HG002 workflow uses a different design

The HG002 example asks where sample reads support variants relative to a
reference, and how those calls compare with a benchmark truth set. Its stages
form a dependency chain because each needs the preceding output:

1. **GIAB data preparation** extracts a requested GRCh38 autosomal interval
   and prepares paired FASTQ, reference, known-sites, truth, confident-region,
   and RTG reference resources. Preparation accepts chr1–chr22, but retained
   end-to-end evidence covers chr20 and two chr21 intervals only.
2. **BWA-MEM** aligns reads to the selected reference and records read-group
   metadata. Alignment estimates where reads fit; it does not decide the final
   genotype at a site.
3. **samtools** converts and sorts alignments. Name sorting groups mates for
   `fixmate`; coordinate sorting enables duplicate marking and indexed
   reference-coordinate access. `markdup` flags duplicate reads, and coverage
   is summarized for the requested interval.
4. **GATK BaseRecalibrator and ApplyBQSR** use the separate known-sites VCF to
   estimate and adjust systematic base-quality errors. This resource is not
   the truth set used to judge calls.
5. **GATK HaplotypeCaller** examines recalibrated alignments and emits
   candidate variants in VCF format.
6. **RTG `vcfeval`** compares calls with the GIAB truth VCF, restricted to the
   confident-region BED and using the matching RTG reference SDF. Calls
   outside confident regions are unscored, not automatically false positives.

The HG002 Nextflow DAG makes sequential dependencies explicit and lets
Nextflow track task inputs, outputs, and execution. Its container packages the
Python project and command-line benchmark tools. The separate generic
benchmark also runs direct tool commands and SeqCheckFlow wrappers against the
same inputs; matching call records support wrapper parity for that tested run,
not general accuracy or superiority. RNA-seq does not need this
alignment/BAM/recalibration/calling chain because its endpoint is expression
quantification rather than genomic variant calls.

### Other execution and comparison technologies

- **Docker** supplies workflow-specific software environments. Images reduce
  dependence on host-installed bioinformatics tools, but reproducibility still
  depends on image versions/digests, source data, references, parameters, host
  resources, and external network services. The RNA-seq and HG002 images serve
  different tool stacks.
- **Nextflow DSL2** expresses processes, inputs, outputs, and dependencies. A
  `docker` profile runs tasks in containers locally. The optional `awsbatch`
  profile submits tasks to a user-provided AWS Batch queue and stages work and
  published outputs through S3. It does not create AWS infrastructure and has
  not been verified by a live AWS run in this project.
- **RTG `vcfeval`** evaluates calls against a baseline truth set using
  variant-aware matching. It is an evaluation tool, not a caller. Precision,
  recall, and F1 describe only the variants and regions scored.
- **BLAST** is an optional standalone helper that submits queries to NCBI's
  remote service. It is not a stage in either Nextflow analysis, and similarity
  results are not proof of biological function.

## Software questions

**What should happen when an input file is malformed?**
SeqCheckFlow should reject it, identify the format and validation problem, and stop
before presenting success-shaped analysis output. The CLI reports an error
and exits unsuccessfully. FASTA/FASTQ/VCF validators check their supported
structural rules; BAM/CRAM integrity checks use `samtools quickcheck`. Passing
format validation does not guarantee biological correctness.

**Where should raw data live?**
Use `data/raw/` for source inputs that should remain unchanged. Raw data is
ignored by Git; do not commit sensitive or large sample data. Download helpers
can also save to `data/` by default, with VCFs under `data/variants/` and
BAM/CRAM under `data/alignments/`.

**Where should processed data live?**
Keep derived data under `data/processed/` when it needs to be retained as an
intermediate. QC and benchmark reports belong in `results/`. The regional GIAB
benchmark inputs live under `data/benchmark/`. Generated/large data directories
are ignored by Git; keep the small directory placeholders as needed.

**What information should be preserved in metadata?**
At minimum preserve sample identity (without exposing private identifiers),
reference assembly and contig/region, input paths and checksums, tool names and
versions, command parameters, filters, known-sites and truth-set versions,
workflow implementation, and run date/environment. For benchmark reproducibility,
also preserve per-stage wall time, CPU/RSS measurements, output sizes, and
truth-evaluation definitions. SeqCheckFlow's full benchmark records many of these
fields and hashes the reads, reference, known-sites file, truth VCF, confident
regions, and reference SDF.

**Which steps should be reproducible?**
All transformations from source inputs to reported metrics should be
re-runnable: data selection and region definition, reference/resource
preparation, validation, alignment, sorting/duplicate handling, BQSR, variant
calling, and truth-set scoring. Pin tool versions and parameters, keep inputs
immutable, record checksums and environment details, and use the same
confident-region/filter definitions when comparing runs. Identical settings
improve repeatability but do not guarantee bit-for-bit-identical timing or
outputs across machines.

**Which external programs are required?**
Requirements depend on the selected path:

- Core Python analysis uses Python plus dependencies in `requirements.txt`
  (currently Biopython and psutil).
- BAM/CRAM validation and summaries require `samtools`.
- Read alignment requires `bwa` (or `minimap2` for the standalone alignment
  wrapper); the integrated benchmark uses BWA.
- The end-to-end germline benchmark additionally uses GATK, `bcftools`, and
  RTG Tools. The supplied Docker environment pins these versions.
- SRA-to-FASTQ download requires NCBI SRA Toolkit's `fasterq-dump`.
- BLAST is submitted to NCBI's remote service through Biopython; it requires
  network access rather than a local BLAST executable.

## Current scope reminder

`seqcheckflow.pipeline` validates and summarizes one supplied FASTA, FASTQ, VCF,
BAM, or CRAM at a time. It does not automatically download, align, or call
variants. The separate HG002 benchmark connects paired FASTQ alignment to
variant calling and truth evaluation for a defined small region. See
[ARCHITECTURE.md](./ARCHITECTURE.md) for the component map and these workflow
boundaries.
