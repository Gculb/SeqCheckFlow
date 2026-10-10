def iter_fastq(filename):
    """Yield FASTQ records one at a time, keeping memory independent of file size."""
    with open(filename, "r", encoding="utf-8") as file_handle:
        record_number = 0
        while True:
            lines = [file_handle.readline() for _ in range(4)]
            if not lines[0]:
                return
            if any(not line for line in lines):
                raise ValueError("FASTQ file ends with an incomplete four-line record.")
            record_number += 1
            identifier, sequence, plus, quality = [line.rstrip("\r\n") for line in lines]

            if not identifier.startswith("@") or len(identifier) == 1:
                raise ValueError(f"Invalid FASTQ identifier on record {record_number}.")

            if not plus.startswith("+"):
                raise ValueError(f"Invalid FASTQ separator on record {record_number}.")

            if len(sequence) != len(quality):
                raise ValueError(
                    f"Sequence and quality lengths do not match for {identifier}"
                )

            yield {"id": identifier[1:], "sequence": sequence, "quality": quality}


def read_fastq(filename):
    """Return all FASTQ records (convenience API for small files)."""
    return list(iter_fastq(filename))

def mean_read_length(reads):
    if not reads:
        return 0

    return sum(len(read["sequence"]) for read in reads) / len(reads)
