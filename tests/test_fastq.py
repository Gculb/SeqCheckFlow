import os
import tempfile
import unittest

from seqcheckflow.fastq import iter_fastq, read_fastq


class FastqParserTests(unittest.TestCase):
    def test_iter_fastq_yields_records_in_order(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".fastq", encoding="utf-8", delete=False
        ) as file_handle:
            file_handle.write("@read1 comment\nACGT\n+\nIIII\n@read2\nGG\n+read2\n!!\n")
            filename = file_handle.name

        try:
            records = list(iter_fastq(filename))
        finally:
            os.unlink(filename)

        self.assertEqual(
            records,
            [
                {"id": "read1 comment", "sequence": "ACGT", "quality": "IIII"},
                {"id": "read2", "sequence": "GG", "quality": "!!"},
            ],
        )

    def test_read_fastq_remains_a_list_convenience_api(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".fastq", encoding="utf-8", delete=False
        ) as file_handle:
            file_handle.write("@read\nA\n+\nI\n")
            filename = file_handle.name

        try:
            records = read_fastq(filename)
        finally:
            os.unlink(filename)

        self.assertIsInstance(records, list)
        self.assertEqual(records[0]["id"], "read")

    def test_iter_fastq_rejects_incomplete_record(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".fastq", encoding="utf-8", delete=False
        ) as file_handle:
            file_handle.write("@read\nACGT\n+\n")
            filename = file_handle.name

        try:
            with self.assertRaisesRegex(ValueError, "incomplete four-line record"):
                list(iter_fastq(filename))
        finally:
            os.unlink(filename)


if __name__ == "__main__":
    unittest.main()
