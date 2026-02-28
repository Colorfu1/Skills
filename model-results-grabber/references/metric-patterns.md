# Metric Patterns (Training / Validation)

This file lists common log patterns to search when extracting results from ML jobs.

## Training Progress (common)

Look for keys like:

- `loss`
- `lr`
- `eta`
- `time`
- `data_time`
- `iter`
- `epoch`

Common strategy:

1. Fetch the last 100-200 lines of `worker_0` logs
2. Search for the latest training metric line
3. Extract current epoch/iter and latest loss/lr

## Validation / Evaluation (common)

Look for keys like:

- `mAP`
- `bbox_mAP`
- `AP`
- `NDS`
- `acc`
- `AUC`
- `Recall`
- `Precision`

Common strategy:

1. Search tail logs for validation/eval markers
2. If absent, fetch more lines (for example `-l 500`)
3. Report latest and best values if both are visible

## MMDet / MMDet3D Hints

Often useful search terms:

- `bbox_mAP`
- `Evaluating`
- `Evaluation`
- `Saving checkpoint`
- `best`
- `Epoch(` or `Epoch [`

If logs include both training and final eval in one run, separate the result summary by phase.

