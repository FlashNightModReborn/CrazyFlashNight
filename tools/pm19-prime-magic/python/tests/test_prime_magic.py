from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from prime_magic.compiler import (
    CompilerConfig,
    SearchStats,
    _find_zero_assignment,
    compile_upgrade,
)
from prime_magic.verify import (
    decode_binary,
    encode_binary,
    is_prime_u64,
    verify_matrix,
)


PROJECT = Path(__file__).resolve().parents[2]


class PrimalityTests(unittest.TestCase):
    def test_known_values_and_strong_pseudoprimes(self) -> None:
        for value in (2, 3, 37, 9_666_061, 10_254_767, 18_446_744_073_709_551_557):
            self.assertTrue(is_prime_u64(value), value)
        for value in (-1, 0, 1, 4, 9, 341, 561, 1_105, 3_215_031_751):
            self.assertFalse(is_prime_u64(value), value)

    def test_rejects_out_of_range(self) -> None:
        with self.assertRaises(ValueError):
            is_prime_u64(1 << 64)


class VerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        payload = json.loads((PROJECT / "seeds/prime_magic_19_seed_00.json").read_text())
        cls.matrix = payload["matrix"]
        cls.magic_sum = payload["magicSum"]

    def test_full_seed(self) -> None:
        report = verify_matrix(self.matrix, expected_magic_sum=self.magic_sum)
        self.assertTrue(report.valid, report.errors)
        self.assertTrue(report.complete_magic)
        self.assertEqual(report.element_count, 361)

    def test_binary_round_trip(self) -> None:
        data = encode_binary(self.matrix, self.magic_sum)
        decoded, decoded_sum = decode_binary(data)
        self.assertEqual(decoded, self.matrix)
        self.assertEqual(decoded_sum, self.magic_sum)

    def test_declared_sum_and_checksum_are_binding(self) -> None:
        wrong_sum = verify_matrix(self.matrix, expected_magic_sum=self.magic_sum + 2)
        self.assertFalse(wrong_sum.valid)
        self.assertFalse(wrong_sum.expected_magic_sum_matches)
        wrong_checksum = verify_matrix(self.matrix, expected_checksum="sha256:" + "0" * 64)
        self.assertFalse(wrong_checksum.valid)
        self.assertFalse(wrong_checksum.serialized_checksum_matches)
        malformed_checksum = verify_matrix(self.matrix, expected_checksum=123)  # type: ignore[arg-type]
        self.assertFalse(malformed_checksum.valid)
        self.assertIn("declared canonical checksum is not a string", malformed_checksum.errors)
        missing_checksum = verify_matrix(self.matrix, require_checksum=True)
        self.assertFalse(missing_checksum.valid)
        self.assertFalse(missing_checksum.serialized_checksum_matches)

        wrong_dimension = verify_matrix(self.matrix, expected_dimension=1)
        self.assertFalse(wrong_dimension.valid)
        self.assertFalse(wrong_dimension.dimension_matches_declaration)

        missing_dimension = verify_matrix(
            self.matrix, require_declared_dimension=True
        )
        self.assertFalse(missing_dimension.valid)
        self.assertFalse(missing_dimension.dimension_matches_declaration)

        missing_sum = verify_matrix(
            self.matrix, require_declared_magic_sum=True
        )
        self.assertFalse(missing_sum.valid)
        self.assertFalse(missing_sum.magic_sum_declaration_valid)

        malformed_sum = verify_matrix(self.matrix, expected_magic_sum=True)
        self.assertFalse(malformed_sum.valid)
        self.assertFalse(malformed_sum.magic_sum_declaration_valid)

    def test_detects_each_basic_failure(self) -> None:
        duplicate = [row[:] for row in self.matrix]
        duplicate[0][0] = duplicate[0][1]
        report = verify_matrix(duplicate)
        self.assertFalse(report.valid)
        self.assertFalse(report.global_uniqueness)
        self.assertFalse(report.row_column_sum_match)

        composite = [row[:] for row in self.matrix]
        composite[0][0] = 9
        report = verify_matrix(composite)
        self.assertFalse(report.primality)

        malformed = [row[:] for row in self.matrix]
        malformed[0].pop()
        report = verify_matrix(malformed)
        self.assertFalse(report.valid)
        self.assertEqual(report.element_count, 360)

    def test_binary_encoder_rejects_ambiguous_inputs(self) -> None:
        invalid = (
            ([], 0),
            ([[2, 3], [5]], 5),
            ([[True]], 1),
            ([[4_294_967_311]], 4_294_967_311),
        )
        for matrix, magic_sum in invalid:
            with self.subTest(matrix=matrix):
                with self.assertRaises(ValueError):
                    encode_binary(matrix, magic_sum)


class CompilerTests(unittest.TestCase):
    def test_assignment_detects_exact_hit_on_final_allowed_move(self) -> None:
        class IdentityRng:
            def shuffle(self, values: list[int]) -> None:
                return None

            def randbelow(self, _bound: int) -> int:
                return 0

        weights = [[1, 0, 100], [0, 0, 100], [100, 100, 0]]
        config = CompilerConfig(
            assignment_restarts=1,
            assignment_steps=1,
            assignment_kick_swaps=1,
        )
        result = _find_zero_assignment(weights, IdentityRng(), config, SearchStats())
        self.assertIsNotNone(result)
        self.assertEqual(sum(weights[row][column] for row, column in enumerate(result or [])), 0)

    def test_deterministic_upgrade_and_exact_diagonals(self) -> None:
        source = json.loads((PROJECT / "fixtures/prime_semimagic_19.json").read_text())
        config = CompilerConfig(
            seed=10_938_693_449_418_882_334,
            outer_attempts=4,
            assignment_restarts=128,
            involution_restarts=128,
        )
        first = compile_upgrade(source["matrix"], source["line_sum"], config)
        second = compile_upgrade(source["matrix"], source["line_sum"], config)
        self.assertEqual(first.matrix, second.matrix)
        report = verify_matrix(first.matrix, expected_magic_sum=source["line_sum"])
        self.assertTrue(report.valid, report.errors)


class CliIntegrityTests(unittest.TestCase):
    def run_python(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PYTHONPATH"] = str(PROJECT / "python")
        return subprocess.run(
            [sys.executable, *arguments],
            cwd=PROJECT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )

    def test_seed_cli_requires_declared_size_sum_and_string_checksum(self) -> None:
        original = json.loads((PROJECT / "seeds/prime_magic_19_seed_00.json").read_text())
        mutations = (
            ("size", lambda payload: payload.__setitem__("size", 1)),
            ("magicSum", lambda payload: payload.pop("magicSum")),
            ("checksum", lambda payload: payload.__setitem__("checksum", 123)),
            ("format", lambda payload: payload.__setitem__("format", "prime-magic-seed/v999")),
        )
        with tempfile.TemporaryDirectory() as temporary:
            for name, mutate in mutations:
                with self.subTest(name=name):
                    payload = json.loads(json.dumps(original))
                    mutate(payload)
                    path = Path(temporary) / f"bad-{name}.json"
                    path.write_text(json.dumps(payload), encoding="utf-8")
                    completed = self.run_python("-m", "prime_magic.verify", str(path))
                    self.assertEqual(completed.returncode, 1)
                    report = json.loads(completed.stdout)
                    self.assertFalse(report["valid"])
                    self.assertTrue(report["errors"])

    def test_manifest_top_level_magic_sum_is_binding(self) -> None:
        source_directory = PROJECT / "seeds"
        payload = json.loads((source_directory / "manifest.json").read_text())
        payload["magicSum"] = 2
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary)
            for record in payload["seeds"]:
                for kind in ("json", "binary"):
                    name = record["files"][kind]
                    shutil.copy2(source_directory / name, destination / name)
            manifest = destination / "manifest.json"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            completed = self.run_python(
                str(PROJECT / "python/verify_manifest.py"), str(manifest)
            )
            self.assertEqual(completed.returncode, 1)
            report = json.loads(completed.stdout)
            self.assertFalse(report["valid"])
            self.assertTrue(
                any("manifest magicSum" in error for error in report["errors"])
            )

    def test_checkpoint_resume_rejects_missing_completed_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "seeds"
            checkpoint = Path(temporary) / "checkpoint.json"
            command = (
                "-m",
                "prime_magic.compiler",
                str(PROJECT / "fixtures/prime_semimagic_19.json"),
                "--output-dir",
                str(output),
                "--seed",
                "20260805",
                "--count",
                "1",
                "--checkpoint",
                str(checkpoint),
            )
            first = self.run_python(*command)
            self.assertEqual(first.returncode, 0, first.stderr)
            (output / "prime_magic_19_seed_00.bin").unlink()
            resumed = self.run_python(*command)
            self.assertNotEqual(resumed.returncode, 0)
            self.assertIn("artifact is missing", resumed.stderr)


if __name__ == "__main__":
    unittest.main()
