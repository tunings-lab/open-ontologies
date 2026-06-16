"""AlignmentIndex tests. Skipped unless the [align] extra (hnswlib) is installed.

Run: pip install -e ".[align,dev]" && pytest -q
"""
import pytest

hnswlib = pytest.importorskip("hnswlib")  # noqa: F841

from open_ontologies_lite import AlignmentIndex  # noqa: E402


def test_nearest_neighbour_recovers_match():
    # Three orthogonal-ish concept vectors; query close to the first.
    idx = AlignmentIndex(dim=3)
    idx.add("flw:PC-BAK", [1.0, 0.0, 0.0])
    idx.add("flw:PC-DRY", [0.0, 1.0, 0.0])
    idx.add("flw:PC-VEG", [0.0, 0.0, 1.0])
    idx.build()
    out = idx.query([0.9, 0.1, 0.0], k=2)
    assert out[0].id == "flw:PC-BAK"
    assert out[0].score > out[1].score  # best candidate ranks first
    assert 0.0 <= out[0].score <= 1.0


def test_dim_mismatch_raises():
    idx = AlignmentIndex(dim=4)
    with pytest.raises(ValueError):
        idx.add("x", [1.0, 2.0, 3.0])


def test_len_and_empty_query():
    idx = AlignmentIndex(dim=2)
    assert len(idx) == 0
    assert idx.query([1.0, 0.0]) == []
    idx.add_many([("a", [1.0, 0.0]), ("b", [0.0, 1.0])])
    assert len(idx) == 2
