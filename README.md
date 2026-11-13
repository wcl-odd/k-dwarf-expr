# DWARF Expression Semantics in K

Executable operational semantics of DWARF expressions in the K Framework, with LLDB/GDB test cases and validation scripts. Recorded results accompany the implementation. Run the commands below from this directory.

## Installation

Use Linux x86-64, Python 3.10+, and **K v7.1.337** with the LLVM backend. The validated toolchain uses Java 21 and LLVM/Clang 15.0.7. Python uses only its standard library; no pip packages or debugger installation are needed.

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

`make` delegates to the [standalone K build](semantics/README.md). `validate.py` uses an existing definition, checks each case's requirements, and writes new results without comparing against recorded results. The output directory must not already exist.

To select one source or change concurrency and limits:

```bash
python3 validate.py --source lldb --output build/lldb
python3 validate.py --source gdb --jobs 16 --timeout 120 --depth 10000 --output build/gdb
python3 validate.py --help
```

To select a build directory, use `make BUILD_DIR=/path/to/build` and pass the resulting definition with `--definition /path/to/build/llvm-kompiled`. The semantics directory also documents direct single-expression execution with K tools.

## Options and limits

| Option | Default | Meaning |
| --- | --- | --- |
| `--output` | Required | New output directory |
| `--source` | `all` | `all`, `lldb`, or `gdb` |
| `--definition` | `build/llvm-kompiled` | Existing compiled LLVM definition |
| `--jobs` | `4` | Concurrent cases, from 1 to 16 |
| `--timeout` | `120` | Seconds per K invocation |
| `--depth` | `10000` | Rewrite limit per K invocation; stability probes use a larger limit |

Concurrency is reduced at 24 GiB aggregate process RSS. Owned processes are stopped at 32 GiB RSS or if host available memory falls below 16 GiB. Temporary files and locks stay under `build/`.

Exit codes: **0** = completed without execution faults; **1** = tool failure, timeout, exhausted rewrite limit, or required task not run; **2** = input/environment error; **130** = interruption. Consistent/inconsistent verdicts are reported separately; an inconsistent verdict alone does not cause exit 1.

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
