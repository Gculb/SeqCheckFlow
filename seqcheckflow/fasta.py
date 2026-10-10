def read_fasta(filename):
    sequences = {}

    current_id = None
    current_sequence = []

    with open(filename, "r") as file:
        for line in file:
            line = line.strip()

            if not line:
                continue

            if line.startswith(">"):
                if current_id is not None:
                    sequences[current_id] = "".join(current_sequence)

                current_id = line[1:].split()[0]
                current_sequence = []
            else:
                current_sequence.append(line)

    if current_id is not None:
        sequences[current_id] = "".join(current_sequence)

    return sequences


def gc_content(sequence):
    sequence = sequence.upper()

    if not sequence:
        return 0

    gc = sequence.count("G") + sequence.count("C")

    return (gc / len(sequence)) * 100


def sequence_stats(sequences):
    lengths = [len(sequence) for sequence in sequences.values()]

    if not lengths:
        return {
            "count": 0,
            "min_length": 0,
            "max_length": 0,
            "mean_length": 0
        }

    return {
        "count": len(sequences),
        "min_length": min(lengths),
        "max_length": max(lengths),
        "mean_length": sum(lengths) / len(lengths)
    }


def analyze_fasta(filename):
    """Summarize a FASTA file incrementally without retaining its sequences."""
    count = 0
    total_bases = 0
    gc_bases = 0
    min_length = None
    max_length = 0
    current_length = 0

    def finish_record():
        nonlocal count, total_bases, min_length, max_length, current_length
        count += 1
        total_bases += current_length
        min_length = current_length if min_length is None else min(min_length, current_length)
        max_length = max(max_length, current_length)
        current_length = 0

    with open(filename, "r", encoding="utf-8") as file_handle:
        for raw_line in file_handle:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if count or current_length:
                    finish_record()
                continue
            current_length += len(line)
            upper = line.upper()
            gc_bases += upper.count("G") + upper.count("C")
    # A valid FASTA has a header for every record; validation is performed first.
    if count or current_length:
        finish_record()

    return {
        "count": count,
        "min_length": min_length or 0,
        "max_length": max_length,
        "mean_length": total_bases / count if count else 0,
        "total_bases": total_bases,
        "gc_content": (gc_bases / total_bases * 100) if total_bases else 0,
    }
