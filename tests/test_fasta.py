import os
import tempfile
import unittest

from seqcheckflow.fasta import analyze_fasta


class FastaAnalysisTests(unittest.TestCase):
    def test_analyze_fasta_counts_multiline_records_and_gc(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".fasta", encoding="utf-8", delete=False
        ) as file_handle:
            file_handle.write(">one description\nACG\nTN\n>two\nggcc\n")
            filename = file_handle.name

        try:
            metrics = analyze_fasta(filename)
        finally:
            os.unlink(filename)

        self.assertEqual(metrics["count"], 2)
        self.assertEqual(metrics["total_bases"], 9)
        self.assertEqual(metrics["min_length"], 4)
        self.assertEqual(metrics["max_length"], 5)
        self.assertEqual(metrics["mean_length"], 4.5)
        self.assertAlmostEqual(metrics["gc_content"], 600 / 9)

    def test_analyze_fasta_handles_empty_file(self):
        with tempfile.NamedTemporaryFile(suffix=".fasta", delete=False) as file_handle:
            filename = file_handle.name

        try:
            metrics = analyze_fasta(filename)
        finally:
            os.unlink(filename)

        self.assertEqual(metrics["count"], 0)
        self.assertEqual(metrics["total_bases"], 0)
        self.assertEqual(metrics["gc_content"], 0)


if __name__ == "__main__":
    unittest.main()
