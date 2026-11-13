// Shared domains and pure queries. Failed queries return absent values, not DWARF error categories.
module DWARF-DOMAINS
  imports INT
  imports BOOL
  imports STRING
  imports MAP

  // Brackets keep nested Maps printable by the K 7.1 unparser.
  syntax Map ::= "(" Map ")" [bracket]

  // g uses address width; base(id, encoding, bit_width, byte_size) preserves distinct type identities.
  syntax Ty ::= "g" [symbol(genericType)]
              | base(String, String, Int, Int) [symbol(baseType)]
  // Int carries mathematical values. Const/Breg/Fbreg produce nonnegative bit patterns; signed reads and
  // initial values may be negative.
  syntax Value ::= val(Int, Ty) [symbol(typedValue)]
  // register and memory identify locations without reading their contents. value retains its type;
  // unavailable denotes an empty expression or fragment.
  syntax Purpose ::= "locationPurpose" | "valuePurpose" | "procedurePurpose" | "entryPurpose"
  syntax EvaluationResult ::= LocationResult | scalarResult(Value) [symbol(scalarResult)]
  syntax LocationResult ::= memory(Int) [symbol(memoryLocation)]
                          | register(Int) [symbol(registerLocation)]
                          | value(Value) [symbol(valueLocation)]
                          | "unavailable" [symbol(unavailableLocation)]
                          | bytesValue(ByteBlock) [symbol(bytesLocation)]
                          | composite(Pieces, ObjectBits) [symbol(compositeLocation)]
                          | implicitPointer(Int, Int) [symbol(implicitPointerLocation)]
  // Byte blocks and pieces are not operand-stack entries; separate constructors support arbitrary lengths.
  syntax ByteBlock ::= ".Bytes" [symbol(emptyBytes)]
                     | byteCons(Int, ByteBlock) [symbol(byteCons)]
  // Typed byte-block interpretation follows target byte order; typed constants are not truncated to the address width.
  syntax Int ::= blockLength(ByteBlock) [function]
               | blockUnsigned(ByteBlock, ByteOrder) [function]
  rule blockLength(.Bytes) => 0
  rule blockLength(byteCons(_, B)) => 1 +Int blockLength(B)
  rule blockUnsigned(.Bytes, _) => 0
  rule blockUnsigned(byteCons(N, B), little) => N +Int 256 *Int blockUnsigned(B, little)
  rule blockUnsigned(byteCons(N, B), big) =>
    N *Int (256 ^Int blockLength(B)) +Int blockUnsigned(B, big)
  syntax Piece ::= bytePiece(Int, LocationResult) [symbol(bytePiece)]
                 | bitPiece(Int, Int, LocationResult) [symbol(bitPiece)]
  syntax Pieces ::= ".Pieces" [symbol(emptyPieces)]
                  | appendPiece(Pieces, Piece) [symbol(appendPiece)]
  // objectBits(length, value, known-bit mask): all three fields are mathematical Ints.
  syntax ObjectBits ::= objectBits(Int, Int, Int) [symbol(objectBits)]
  syntax OptionalBits ::= someBits(ObjectBits) | "noBits"
  syntax PendingLocation ::= "noLocation" | located(LocationResult)
  syntax FragmentState ::= fragments(Int, PendingLocation, Pieces, ObjectBits, Bool) [symbol(fragments)]
  // push(S,V) places V on top of S; .Stack is empty.
  syntax Stack ::= ".Stack" [symbol(emptyStack)]
                 | push(Stack, Value) [symbol(stackPush)]
  syntax ByteOrder ::= "little" | "big"
  // Optional values: some... carries a result, no... means absent; someInt(0) differs from noInt.
  syntax OptionalInt ::= "noInt" | someInt(Int)
  // Register widths are separate from stack-value types. Int register entries use address width; wider
  // registerBits entries retain their high bits.
  syntax RegisterContent ::= registerBits(Int, Int) [symbol(registerBits)]
                           | unavailableRegister(Int) [symbol(unavailableRegister)]
  // Wasm input data are retained for compatibility; Wasm operations are unsupported.
  syntax WasmSlot ::= wasmSlot(Int, Int) [symbol(wasmSlot)]
  syntax MemoryRequest ::= memoryRequest(Int, Int) [symbol(memoryRequest)]
                         | "requestMemoryMode" [symbol(requestMemoryMode)]
  syntax OptionalType ::= "noType" | someType(Ty)
  // Preserve supplied DIE attributes, including unsupported or incomplete types, for K lookup and audit.
  syntax RawType ::= rawType(String, String, String, OptionalInt, OptionalInt, String) [symbol(rawType)]
  syntax OptionalValue ::= "noValue" | someValue(Value)
  // Read-only context: address width in bits, byte order, type/register tables, byte memory, frame base,
  // CFA, architecture, address table, bias, and object address.
  syntax Architecture ::= "unspecified" | "i386" | "x86_64" | "aarch64"
  // DEBUGADDR belongs to the current CU; BIAS applies only to addrx. OBJECT is independent of frame base
  // and CFA.
  syntax Context ::= ctx(Int, ByteOrder, Map, Map, Map, OptionalInt, OptionalInt, Architecture, Map, Int, OptionalInt)


  // Optional metadata use the string key runtime, separate from integer type references. Missing lookups
  // remain unknown; preparedDIE holds decoded code.
  syntax DecodedExpression
  syntax DIEBody ::= dieBody(ByteBlock, Int, Int, Int, Map, Map, OptionalInt, Int, Int) [symbol(dieBody)]
                   | preparedDIE(DIEBody, DecodedExpression) [symbol(preparedDIE)]
  syntax OptionalDIE ::= someDIE(DIEBody) | "noDIE"
  syntax Map ::= runtimeData(Context) [function]
               | runtimeTable(Context, String) [function]
  rule runtimeData(ctx(_, _, ("runtime" |-> M:Map) _:Map, _, _, _, _, _, _, _, _)) => M
  rule runtimeData(_) => .Map [owise]
  rule runtimeTable(C, NAME) => runtimeMap(runtimeData(C), NAME)
  syntax Map ::= runtimeMap(Map, String) [function]
  rule runtimeMap((NAME |-> M:Map) _:Map, NAME) => M
  rule runtimeMap(_, _) => .Map [owise]
  syntax Int ::= runtimeNumber(Context, String, Int) [function]
               | runtimeNumberFrom(Map, String, Int) [function]
  rule runtimeNumber(C, NAME, DEFAULT) => runtimeNumberFrom(runtimeData(C), NAME, DEFAULT)
  rule runtimeNumberFrom((NAME |-> N:Int) _:Map, NAME, _) => N
  rule runtimeNumberFrom(_, _, DEFAULT) => DEFAULT [owise]
  syntax OptionalDIE ::= lookupDIE(Map, Int) [function]
  rule lookupDIE((REF |-> D:DIEBody) _:Map, REF) => someDIE(D)
  rule lookupDIE(_, _) => noDIE [owise]
  syntax Bool ::= hasType(OptionalType) [function]
  rule hasType(someType(_)) => true
  rule hasType(noType) => false
  syntax Bool ::= hasDIE(OptionalDIE) [function]
  rule hasDIE(someDIE(_)) => true
  rule hasDIE(noDIE) => false
  syntax DIEBody ::= getDIE(OptionalDIE) [function]
  rule getDIE(someDIE(D)) => D
  syntax OptionalContext ::= someContext(Context) [symbol(someContext)] | "noContext" [symbol(noContext)]
  syntax OptionalContext ::= entryContext(Context) [function]
  rule entryContext(ctx(_, _, ("runtime" |-> (("entry" |-> C:Context) _:Map)) _:Map, _, _, _, _, _, _, _, _)) => someContext(C)
  rule entryContext(_) => noContext [owise]
  syntax Bool ::= hasContext(OptionalContext) [function]
  rule hasContext(someContext(_)) => true
  rule hasContext(noContext) => false
  syntax Context ::= getContext(OptionalContext) [function]
  rule getContext(someContext(C)) => C
  syntax OptionalInt ::= readAddressSpace(Context, Int, Int, Int) [function]
  rule readAddressSpace(ctx(A, E, _, _, _, _, _, _, _, _, _) #as C, SPACE, SIZE, ADDR) =>
    readSpaceMap(runtimeTable(C, "spaces"), SPACE, SIZE, ADDR, A, E)
  syntax OptionalInt ::= readSpaceMap(Map, Int, Int, Int, Int, ByteOrder) [function]
  rule readSpaceMap((SPACE |-> M:Map) _:Map, SPACE, SIZE, ADDR, A, E) => readUnsigned(M, ADDR, SIZE, E)
    requires 0 <=Int SIZE andBool (SIZE ==Int 0 orBool (0 <=Int ADDR andBool ADDR +Int SIZE <=Int 2 ^Int A))
  rule readSpaceMap(_, _, _, _, _, _) => noInt [owise]

  // Source-range checks use W bits without truncation.
  syntax Bool ::= fitsUnsigned(Int, Int) [function]
                | fitsSigned(Int, Int) [function]
  rule fitsUnsigned(N, W) => 0 <=Int N andBool N <Int (2 ^Int W)
  rule fitsSigned(N, W) => (0 -Int (2 ^Int (W -Int 1))) <=Int N
                    andBool N <Int (2 ^Int (W -Int 1))

  syntax OptionalInt ::= lookupInt(Map, Int) [function]
  rule lookupInt((K |-> N:Int) _REST:Map, K) => someInt(N)
  rule lookupInt((K |-> registerBits(N, _)) _REST:Map, K) => someInt(N)
  rule lookupInt((K |-> unavailableRegister(_)) _REST:Map, K) => noInt
  rule lookupInt(M, K) => noInt requires notBool (K in_keys(M))
  syntax Int ::= physicalRegisterWidth(Map, Int, Int) [function]
  rule physicalRegisterWidth((R |-> registerBits(_, W)) _REST:Map, R, _) => W
  rule physicalRegisterWidth((R |-> unavailableRegister(W)) _REST:Map, R, _) => W
  rule physicalRegisterWidth(_, _, DEFAULT) => DEFAULT [owise]
  // Extract a value only after a successful lookup.
  syntax Bool ::= hasInt(OptionalInt) [function]
  rule hasInt(someInt(_)) => true
  rule hasInt(noInt) => false
  syntax Int ::= getInt(OptionalInt) [function]
  rule getInt(someInt(N)) => N
  syntax OptionalType ::= lookupType(Map, Int) [function]
  rule lookupType((K |-> T:Ty) _REST:Map, K) => someType(T) requires supportedType(T)
  rule lookupType((K |-> T:Ty) _REST:Map, K) => noType requires notBool supportedType(T)
  rule lookupType((K |-> T:RawType) _REST:Map, K) => resolveRawType(T)
  rule lookupType(M, K) => noType requires notBool (K in_keys(M))
  syntax Bool ::= numericEncoding(String) [function]
  rule numericEncoding(E) => E ==String "DW_ATE_address" orBool E ==String "DW_ATE_boolean"
    orBool E ==String "DW_ATE_signed" orBool E ==String "DW_ATE_signed_char"
    orBool E ==String "DW_ATE_unsigned" orBool E ==String "DW_ATE_unsigned_char"
    orBool E ==String "DW_ATE_UTF" orBool E ==String "DW_ATE_UCS" orBool E ==String "DW_ATE_ASCII"
    orBool E ==String "DW_ATE_float"
  // Unknown encodings and unmodeled floating-point formats do not fall through to integer handling.
  syntax Bool ::= integerType(Ty) [function]
                | supportedType(Ty) [function]
  rule integerType(g) => true
  rule integerType(base(_, E, _, _)) => numericEncoding(E) andBool E =/=String "DW_ATE_float"
  rule supportedType((base(_, E, W, _) #as T)) => integerType(T) orBool
    (E ==String "DW_ATE_float" andBool
      (W ==Int 32 orBool W ==Int 64 orBool W ==Int 80 orBool W ==Int 128))
  rule supportedType(g) => true
  syntax OptionalType ::= resolveRawType(RawType) [function]
  rule resolveRawType(rawType(ID, "DW_TAG_base_type", E, someInt(W), someInt(B), _)) => someType(base(ID, E, W, B))
    requires supportedType(base(ID, E, W, B)) andBool 0 <Int W andBool 0 <Int B andBool W <=Int 8 *Int B
  rule resolveRawType(rawType(ID, "DW_TAG_base_type", E, noInt, someInt(B), _)) => someType(base(ID, E, 8 *Int B, B))
    requires supportedType(base(ID, E, 8 *Int B, B)) andBool 0 <Int B
  // A type with only bit_size uses the minimum containing byte count.
  rule resolveRawType(rawType(ID, "DW_TAG_base_type", E, someInt(W), noInt, _)) => someType(base(ID, E, W, (W +Int 7) /Int 8))
    requires supportedType(base(ID, E, W, (W +Int 7) /Int 8)) andBool 0 <Int W
  rule resolveRawType(_) => noType [owise]

  // Depth zero is the stack top; absent or negative indices return noValue. DW_OP_pick separately enforces
  // its byte-sized index.
  syntax OptionalValue ::= stackAt(Stack, Int) [function]
  rule stackAt(push(_, V), 0) => someValue(V)
  rule stackAt(push(S, _), K) => stackAt(S, K -Int 1) requires K >Int 0
  rule stackAt(.Stack, _) => noValue
  rule stackAt(push(_, _), K) => noValue requires K <Int 0

  // noValue has no default Value; getValue requires a successful query.
  syntax Bool ::= hasValue(OptionalValue) [function]
  rule hasValue(someValue(_)) => true
  rule hasValue(noValue) => false
  syntax Value ::= getValue(OptionalValue) [function]
  rule getValue(someValue(V)) => V

  // readUnsigned(M,A,S,E) reads S bytes from address A in byte order E. Callers check ranges and types.
  syntax OptionalInt ::= readUnsigned(Map, Int, Int, ByteOrder) [function]
                       | combineByte(OptionalInt, OptionalInt, Int, ByteOrder) [function]
  // Zero-byte reads return zero without memory access; negative sizes have no result.
  rule readUnsigned(_, _, 0, _) => someInt(0)
  rule readUnsigned(M, A, S, E) =>
    combineByte(lookupInt(M, A), readUnsigned(M, A +Int 1, S -Int 1, E), S, E)
    requires S >Int 0
  rule readUnsigned(_, _, S, _) => noInt requires S <Int 0
  // B is the lowest-addressed byte: little places it in the low bits, big in the high bits.
  rule combineByte(someInt(B), someInt(N), _, little) => someInt(B +Int (256 *Int N))
  rule combineByte(someInt(B), someInt(N), S, big) => someInt((B *Int (256 ^Int (S -Int 1))) +Int N)
  // Missing bytes propagate noInt.
  rule combineByte(noInt, _, _, _) => noInt
  rule combineByte(someInt(_), noInt, _, _) => noInt

  // Only signed and signed_char interpret integral reads as signed; Boolean reads remain unsigned without
  // normalization.
  syntax Bool ::= signedEncoding(String) [function]
  rule signedEncoding(E) => E ==String "DW_ATE_signed" orBool E ==String "DW_ATE_signed_char"
  syntax Int ::= bits(Int, Int) [function, symbol(unsignedLow(_,_)_DWARF-DOMAINS_Int_Int_Int)]
               | signedBits(Int, Int) [function, symbol(signedLow(_,_)_DWARF-DOMAINS_Int_Int_Int)]
               | interpret(Int, Ty) [function]
  // For positive W, bits keeps [0,2^W); signedBits interprets the same pattern as W-bit two's complement.
  rule bits(N, W) => N modInt (2 ^Int W)
  rule signedBits(N, W) => ((N +Int (2 ^Int (W -Int 1))) modInt (2 ^Int W))
                          -Int (2 ^Int (W -Int 1))
  // Generic reads are unsigned at address width. Base types interpret their low W effective bits by
  // encoding; storage padding is ignored.
  rule interpret(N, g) => N
  rule interpret(N, base(_, E, W, _)) => signedBits(N, W) requires signedEncoding(E)
  rule interpret(N, base(_, E, W, _)) => bits(N, W) requires numericEncoding(E) andBool notBool signedEncoding(E)

  // Generic reads permit zero bytes but at most A bits. Typed reads require the exact positive byte_size;
  // the operation checks the 0..255 size field.
  syntax Bool ::= validReadSize(Int, Ty, Int) [function]
  rule validReadSize(S, g, A) => 0 <=Int S andBool (8 *Int S) <=Int A
  rule validReadSize(S, (base(_, _, _, B) #as T), _) => supportedType(T) andBool S ==Int B

  // Nonzero reads must stay inside the A-bit address space without wrapping. Zero-size reads return zero
  // without restricting ADDR; callers check type capacity.
  syntax OptionalInt ::= readMemory(Context, Int, Int) [function]
  rule readMemory(ctx(A, E, _, _, M, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt), SIZE, ADDR) =>
    readUnsigned(M, ADDR, SIZE, E)
    requires 0 <=Int SIZE
      andBool (SIZE ==Int 0 orBool (0 <=Int ADDR andBool ADDR +Int SIZE <=Int (2 ^Int A)))
      andBool notBool (requestMemoryMode in_keys(M))
  rule readMemory(ctx(A, E, _, _, M, _, _, _, _, _, _), SIZE, ADDR) => readRequest(M, ADDR, SIZE, E)
    requires (requestMemoryMode in_keys(M)) andBool 0 <=Int SIZE
      andBool (SIZE ==Int 0 orBool (0 <=Int ADDR andBool ADDR +Int SIZE <=Int (2 ^Int A)))
  rule readMemory(_, _, _) => noInt [owise]
  // LLDB read fixtures are keyed by (address, length); overlapping reads can disagree. Keep each request
  // independent, without merging or zero-filling.
  syntax OptionalInt ::= readRequest(Map, Int, Int, ByteOrder) [function]
  rule readRequest(_, _, 0, _) => someInt(0)
  rule readRequest((memoryRequest(ADDR, SIZE) |-> B:ByteBlock) _REST:Map, ADDR, SIZE, E) => someInt(blockUnsigned(B, E))
    requires SIZE >Int 0 andBool blockLength(B) ==Int SIZE
  rule readRequest(_, _, _, _) => noInt [owise]

  // Typed reads check storage size and interpret the effective bits while preserving type identity.
  syntax OptionalValue ::= readTypedValue(Context, Int, OptionalType, Int) [function]
                         | interpretRead(OptionalInt, Ty) [function]
  rule readTypedValue(ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C, SIZE, someType(T), ADDR) =>
    interpretRead(readMemory(C, SIZE, ADDR), T)
    requires validReadSize(SIZE, T, A)
  rule readTypedValue(_, _, _, _) => noValue [owise]

  // Missing bytes produce noValue; a successful read retains type T.
  rule interpretRead(someInt(N), T) => someValue(val(interpret(N, T), T)) requires supportedType(T)
  rule interpretRead(_, _) => noValue [owise]
endmodule
