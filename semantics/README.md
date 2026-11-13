# Executable DWARF expression semantics

Standalone K definitions and Makefile. Copy this directory independently; no parent-project files, Python scripts, debugger, or test corpus are needed. Run commands from this directory.

## Requirements

Use Linux x86-64, GNU Make, Bash, `flock` (util-linux), and **K v7.1.337** with its LLVM backend and compiler dependencies. The validated toolchain uses Java 21 and LLVM/Clang 15.0.7. Put `kompile`, `kparse`, and `krun` on `PATH`. Follow the [K installation guide](https://kframework.org/docs/getting-started/) and [release instructions](https://github.com/runtimeverification/k/releases/tag/v7.1.337).

## Build

```bash
make
```

This compiles `dwarf.k` into `build/llvm-kompiled`, rebuilding when K sources or the Makefile change. It does not run expressions or tests.

Choose another build directory or an exact definition directory:

```bash
make BUILD_DIR=/path/to/build
make DEFINITION=/path/to/dwarf-llvm-kompiled
```

Relative paths are resolved from this directory, including with `make -C semantics`. Build options are:

| Variable | Default | Meaning |
| --- | --- | --- |
| `BUILD_DIR` | `build` | Build lock and default output parent |
| `BACKEND` | `llvm` | `llvm` or `haskell`; Haskell requires its additional K backend dependencies |
| `DEFINITION` | `$(BUILD_DIR)/$(BACKEND)-kompiled` | Integrated text/bytecode definition |
| `CORE_DEFINITION` | `$(BUILD_DIR)/core-$(BACKEND)-kompiled` | Definition for already decoded expressions |
| `TMP_ROOT` | `$(BUILD_DIR)/tmp` | Parent of private compiler temporary directories |
| `KOMPILE` | `kompile` | Compiler executable |
| `KOMPILE_JAVA_OPTIONS` | `-XX:ActiveProcessorCount=8 -XX:+UseSerialGC` | Compiler JVM options |
| `KOMPILE_K_OPTIONS` | `-Xmx2g -Xss1m` | Compiler JVM heap and stack limits |

For the Haskell backend use `make BACKEND=haskell`. For the execution layer alone use `make core`; its expression input is a `DecodedExpression`, defined in [execution/expression.k](execution/expression.k). The examples below use the integrated LLVM definition.

## Execute an expression

Set the compiled definition path and a temporary directory for the K tools:

```bash
definition="$PWD/build/llvm-kompiled"
mkdir -p build/tmp
export TMPDIR="$PWD/build/tmp"
export JAVA_TOOL_OPTIONS="-XX:ActiveProcessorCount=2 -XX:+UseSerialGC -Djava.io.tmpdir=$TMPDIR"
```

If you selected another definition directory, set `definition` to that path. Create an expression whose result is the direct generic value 7:

```bash
cat > build/expression.dwarf <<'EOF'
0: DW_OP_lit7,
1: DW_OP_stack_value,
2
EOF

kparse build/expression.dwarf --definition "$definition" \
  --module DWARF-TEXT-SYNTAX --sort Input > build/program.kore

krun build/program.kore --definition "$definition" --parser cat \
  -cCONTEXT='ctx(64, little, .Map, .Map, .Map, noInt, noInt, unspecified, .Map, 0, noInt)' \
  -cSTACK='.Stack' -cPURPOSE='locationPurpose' \
  --depth 10000 --color off
```

`kparse` produces KORE; `krun --parser cat` executes it. K parses context, stack, and purpose from the `-c` arguments.

For bytecode, create a whitespace-separated hexadecimal byte file and change the parsing module:

```bash
printf '37 9f\n' > build/expression.hex
kparse build/expression.hex --definition "$definition" \
  --module DWARF-HEX-SYNTAX --sort Input > build/program.kore
```

Run the same `krun` command; both forms finish with `value(val(7,g))` at position 2. Add `--output json --output-file build/result.json` to save the complete configuration as KAST JSON.

## Expression input

| Form | Contents |
| --- | --- |
| Text | `offset: DW_OP_name operands, ... END`, parsed by `DWARF-TEXT-SYNTAX` |
| Bytecode | Whitespace-separated bytes such as `37 9f`, parsed by `DWARF-HEX-SYNTAX` |
| Decoded | `decoded(START, END, INSTRUCTIONS, BYTES)`, accepted by the execution layer |

Text offsets must strictly increase and finish with a standalone END offset. Text uses declared positions rather than checking encoded instruction lengths. Decimal and `0x`/`0X` literals, including negative mathematical integers, are accepted. A text empty expression is `0`.

Each hexadecimal byte has exactly two digits, optionally prefixed by `0x`/`0X`; `379f` is not split into bytes. An empty byte file is an empty expression. Bytecode starts at zero and END is its byte count. K decodes fixed-width operands in the supplied byte order and handles ULEB128/SLEB128 itself. A truncated or unsupported operation leaves only the complete decoded prefix available for execution.

## Interface, initial stack, and purpose

Inputs are K terms: `$PGM` holds the parsed expression, while `-cCONTEXT`, `-cSTACK`, and `-cPURPOSE` supply context, stack, and purpose. This directory has no JSON interface converter.

The interface constructor is:

```text
ctx(A, ORDER, TYPES, REGISTERS, MEMORY, FB, CFA, ARCH, DEBUGADDR, BIAS, OBJECT)
```

| Argument | K representation and units |
| --- | --- |
| `A` | Positive address width in bits |
| `ORDER` | `little` or `big` |
| `TYPES` | Map from positive CU-relative references to base types; `.Map` when absent |
| `REGISTERS` | Map from DWARF register numbers to integer contents or `registerBits(value,width)`; width is in bits |
| `MEMORY` | Sparse map from byte addresses to bytes in 0..255 |
| `FB`, `CFA` | Independently supplied frame base and call frame address: `someInt(address)` or `noInt` |
| `ARCH` | `unspecified`, `i386`, `x86_64`, or `aarch64` |
| `DEBUGADDR` | Map from current-CU address-table indices to nonnegative entries |
| `BIAS` | Integer load bias for `DW_OP_addrx`; not applied to `DW_OP_constx` |
| `OBJECT` | Current-object address: `someInt(address)` or `noInt` |

For example, this interface supplies type reference 12, register 3, two bytes of memory, and a frame base:

```text
ctx(64, little,
    (12 |-> base("s16", "DW_ATE_signed", 16, 2)),
    (3 |-> registerBits(4096, 64)),
    ((4096 |-> 42) (4097 |-> 0)),
    someInt(8192), noInt, x86_64, .Map, 0, noInt)
```

Pass the term as one quoted `-cCONTEXT` argument. Map keys and contents are mathematical integers. `noInt` and omitted register/memory entries mean unknown; `someInt(0)` is known zero. Supply frame base, CFA, entry state, and TLS data externally.

A base type is `base(identity, encoding, effective_bits, storage_bytes)`. Different identities remain distinct. Use positive storage size and `0 < effective_bits <= 8*storage_bytes`; effective width can exceed address width. Signed encodings interpret their own low bits as signed; Boolean and other supported integral encodings use unsigned interpretation. `DW_ATE_float` supports binary32, binary64, x87 binary80, and binary128. Floating values carry raw bits in their integer carrier.

The stack is `.Stack` or `push(PREFIX,val(NUMBER,TYPE))`. Generic type is `g`; a typed entry includes its full `base(...)` term. For example:

```text
push(push(.Stack,val(17,g)),val(255,base("bool8","DW_ATE_boolean",8,1)))
```

The outermost entry is the top. Choose `locationPurpose` for a location description, or `valuePurpose` for a scalar calculation. Value purpose returns the final stack top without interpreting it as an address; location markers such as `DW_OP_stack_value` belong to location purpose.

Called DIE expressions, entry state, and other runtime data use the type map's `"runtime"` key. See [domains/dwarf-domains.k](domains/dwarf-domains.k) and [execution/runtime.k](execution/runtime.k) for constructors required by these operations.

Direct K execution checks syntax and sorts, with no global interface validation. Supply well-formed inputs; operation preconditions govern execution.

## Output and stopping

The default output is the complete K configuration. The example above produces:

```text
<dwarf>
  <expr>
    finished(decoded(...), ctx(...), 2, value(val(7,g)), locationPurpose) ~> .K
  </expr>
  <pc> 2 </pc>
  <stack> push(.Stack,val(7,g)) </stack>
  <fragments> fragments(0,noLocation,.Pieces,objectBits(0,0,0),true) </fragments>
</dwarf>
```

`decoded(...)` and `ctx(...)` are abbreviated here. The fourth argument of `finished` is the result; the stack remains in its cell.

| Result constructor | Meaning |
| --- | --- |
| `memory(address)` | Memory location; the object value is not read |
| `register(number)` | Register location, identified by its DWARF number |
| `value(val(number,type))` | Direct value, including its type |
| `bytesValue(bytes)` | Implicit byte contents |
| `composite(pieces,objectBits(length,data,known_mask))` | Piece descriptions, object bits, and available-bit mask |
| `implicitPointer(reference,offset)` | DIE identity and signed byte offset |
| `unavailable` | Empty expression or genuinely empty fragment |
| `scalarResult(val(number,type))` | Scalar calculation for `valuePurpose` |

`DW_OP_piece` and `DW_OP_bit_piece` require `little` byte order; a big-endian composite stops at its piece delimiter. This model limitation does not establish invalid DWARF.

An unfinished `<expr>` retains `evaluate(...)` and any nested return state. A failed precondition gives no transition: missing inputs, insufficient stack, unsupported types, or arithmetic restrictions can all cause natural stuckness. Structural input checks can instead produce `inputError(...)`. Neither form is a successful `finished(...)` result.

`--depth` bounds K rewrites, not encoded operations. Exhausting the budget can also leave an unfinished configuration; rerun with a larger budget to investigate. At zero depth some backends may retain the configuration initializer. A successful krun process exit alone does not establish semantic completion; inspect the configuration. Parse and tool errors are separate from these K states.

The implementation covers 164 standard DWARF 2–5 operation names with operation-specific preconditions; vendor operations are unsupported.

## Numeric conventions

Integer-to-Boolean conversion normalizes to 0/1, including Boolean-to-Boolean. Boolean sources otherwise use their own unsigned effective width. Boolean/float conversion is unsupported; reads, calculations, and reinterpretation do not normalize Boolean values.

Generic values use address width; base types use their own effective width independently of storage padding. Ordinary constants retain the low address-width bits after source-operand range checks. Integer conversion retains target-width low bits and selects the target encoding's representative; a generic conversion source is interpreted as unsigned at address width. Reinterpretation requires equal effective widths and preserves the bit pattern rather than converting its numeric value.

Floating calculations use exact binary rationals and roundTiesToEven. The implemented floating operations are `abs`, `neg`, `plus`, `minus`, `mul`, `div`, and six comparisons. Float-to-integer conversion truncates toward zero and requires a finite, representable result; NaN, infinity, or an out-of-range target gives no conversion transition. Rounding modes, exception flags, signaling-NaN traps, all padded ABI layouts, and validation of noncanonical x87 encodings are not modeled. Operations restricted by DWARF to integers have no floating transition.

Floating `abs`/`neg` clear/toggle the sign while preserving NaN payload and quiet/signaling bits; binary-arithmetic NaN results are fixed quiet NaNs. Comparisons return 0/1 (only `ne` is true for NaN); same-width floating conversion and reinterpretation preserve bits.

## Source layout

- [dwarf.k](dwarf.k): integrated expression entry.
- [frontend/](frontend/): text syntax, bytecode decoding, and pure preparation.
- [execution/](execution/): decoded expressions, calculations, runtime queries, composition, and execution rules.
- [domains/dwarf-domains.k](domains/dwarf-domains.k): interfaces, types, values, stacks, and results.

The definitions implement the documented model of the [DWARF specification](https://dwarfstd.org/doc/DWARF5.pdf).
