# Internal validation scripts

These modules support `validate.py`. See the [usage guide](../README.md) for commands and options.

| File | Responsibility |
| --- | --- |
| `experiment.py` | Schedules concurrent cases, applies resource limits, and writes reports. |
| `cases.py` | Loads case files and prepares inputs for each K invocation. |
| `dependencies.py` | Schedules attribute expressions and combines their observations with the root case. |
| `k.py` | Invokes the K driver and checks that the supplied expression and interface remain unchanged. |
| `runner.py` | Serializes the interface, invokes K, and reads its final configuration and location result. |
| `requirements.py` | Checks each case's requirements against the K outcome. |
| `processes.py` | Runs child processes, saves their output, and handles timeouts and cleanup. |
