# DWARF Expression Semantics in K

Executable DWARF expression semantics in K. The experiment runs cases prepared from GDB/LLDB tests and checks their saved requirements against K outcomes, without starting either debugger. Run commands from this directory.

## Installation

Use Linux x86-64, Python 3.10+, and **K v7.1.337** with the LLVM backend. The validated toolchain uses Java 21 and LLVM/Clang 15.0.7. Python uses only its standard library; no pip packages or debugger installation are needed.

**Memory:** the runner stops its workers if host available memory falls below **16 GiB**. Leave room for this reserve in addition to worker memory; the other limits are listed below.

Install K and Java following the [K release](https://github.com/runtimeverification/k/releases/tag/v7.1.337) and [installation guide](https://kframework.org/docs/getting-started/). Put `kompile`, `kparse`, `krun`, and `java` on `PATH`. Typical Ubuntu build prerequisites are:

```bash
sudo apt-get install build-essential make cmake pkg-config util-linux \
  clang-15 llvm-15-dev lld-15 libgmp-dev libmpfr-dev libboost-dev \
  libffi-dev libfmt-dev libjemalloc-dev libunwind-dev libz3-dev zlib1g-dev
```

## Build and validate

```bash
make
python3 validate.py --output build/experiment
```

Reference outcome from the recorded experiment: **326 / 326 tasks completed, 0 execution faults, exit code 0**.

| Scope | Tasks | Consistent | Inconsistent | Uncheckable |
| --- | ---: | ---: | ---: | ---: |
| Core | 324 | 310 | 14 | 0 |
| Auxiliary | 2 | 0 | 0 | 2 |

Auxiliary cases cover API/diagnostic requirements not fully represented by K and are excluded from core counts. **Consistent** means all applicable requirements hold; **inconsistent** means at least one is not met. Inconsistency alone does not cause exit code 1.

`make` delegates to the [standalone K build](semantics/README.md). `validate.py` uses an existing definition and writes new results without comparing against recorded results. The output directory must not already exist.

The default is four concurrent cases. For a full run with 16 concurrent cases, or to select one source:

```bash
python3 validate.py --jobs 16 --output build/experiment-16
python3 validate.py --source lldb --output build/lldb
python3 validate.py --source gdb --output build/gdb
python3 validate.py --help
```

Reference timings, excluding installation: **18 seconds to build** and **5 minutes for the full experiment with `--jobs 16`**, on a dual Intel Xeon Gold 6430 host with 128 logical CPUs and about 251 GiB RAM. Times vary with hardware and load.

To select a build directory, use `make BUILD_DIR=/path/to/build` and pass the resulting definition with `--definition /path/to/build/llvm-kompiled`. The semantics directory also documents direct single-expression execution with K tools.

Parser output is cached in `<definition>/input-parse-cache/`, requiring a writable definition directory. Set `DWARF_K_PARSE_CACHE=off` to disable caching for a read-only definition:

```bash
DWARF_K_PARSE_CACHE=off python3 validate.py --definition /path/to/build/llvm-kompiled --output build/uncached
```

## Options and limits

| Option | Default | Meaning |
| --- | --- | --- |
| `--output` | Required | New output directory |
| `--source` | `all` | `all`, `lldb`, or `gdb` |
| `--definition` | `build/llvm-kompiled` | Existing compiled LLVM definition |
| `--jobs` | `4` | Concurrent cases, from 1 to 16 |
| `--timeout` | `120` | Seconds per K invocation |
| `--depth` | `10000` | Rewrite limit per K invocation; stability probes use a larger limit |

Concurrency is reduced at 24 GiB aggregate process RSS. Owned processes are stopped at 32 GiB RSS or at the host available-memory threshold above. Runner temporary files and the experiment lock default to `build/`; the parser cache uses the selected definition directory.

Exit codes: **0** = completed without execution faults; **1** = tool failure, timeout, exhausted rewrite limit, or required task not run; **2** = input/environment error; **130** = interruption.

## Results and reference files

```text
<output>/
├── report.md          Counts, run settings, completion, and faults
├── expressions.csv    One verdict per case
├── checks.csv         One row per requirement
└── <case-id>/         Inputs, commands, checks, and complete K outcomes
```

See the [recorded report](results/report.md) for the paper's results and its CSV/compressed evidence. New runs write the working files above, without adding compressed evidence or manual analyses.

The [case-file guide](test-corpus/README.md) describes the inputs; the [script index](scripts/README.md) lists internal module responsibilities.
