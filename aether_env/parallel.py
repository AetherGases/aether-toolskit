import os
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import TypeVar

T = TypeVar("T")
R = TypeVar("R")

DEFAULT_PUBLISH_WORKERS = 2
DEFAULT_APPLY_WORKERS = 8
DEFAULT_TEARDOWN_WORKERS = 8


def worker_count(item_count: int, default: int) -> int:
    if item_count <= 1:
        return 1
    limit = max(1, min(default, (os.cpu_count() or 4) * 2))
    return min(item_count, limit)


def run_parallel(items: Iterable[T], worker: Callable[[T], R], *, max_workers: int) -> list[R]:
    batch = list(items)
    if not batch:
        return []
    workers = worker_count(len(batch), max_workers)
    if workers == 1:
        return [worker(item) for item in batch]
    results: list[R | None] = [None] * len(batch)
    indexed = list(enumerate(batch))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(worker, item): index for index, item in indexed}
        for future in as_completed(futures):
            index = futures[future]
            results[index] = future.result()
    return [item for item in results if item is not None]
