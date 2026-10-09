from aether_env.parallel import run_parallel, worker_count


def test_worker_count_caps_parallelism():
    assert worker_count(1, 8) == 1
    assert worker_count(3, 8) == 3
    assert worker_count(100, 4) == 4


def test_run_parallel_preserves_order():
    values = run_parallel([1, 2, 3], lambda item: item * 2, max_workers=8)
    assert values == [2, 4, 6]
