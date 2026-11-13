# Expression cases

| File | Core expression cases | Auxiliary checks |
| --- | ---: | ---: |
| `lldb.json` | 55 | 2 |
| `gdb.json` | 269 | 0 |

Each JSON file contains a `cases` array. Each case has the following fields:

| Field | Contents |
| --- | --- |
| `expression` | Hexadecimal bytecode, evaluation purpose, and attribute dependencies |
| `interface` | Fixed external inputs: address width, byte order, registers, sparse memory, and debug metadata |
| `requirements` | Predicates on the K outcome, with object layout and observation inputs where needed |
| `id`, `tool` | Case identifier and source tool |
| `group` | Core or auxiliary classification; used only for reporting, not supplied to K |
| `source` | Upstream file, test name, and original assertion; documentation only, ignored by the runner |

Only core cases enter the core result counts. Attribute dependencies belong to their root case and do not add cases. Omitted interface entries remain unknown; empty bytecode is a genuine empty expression.

See the [usage guide](../README.md) for installation, commands, and output files.
