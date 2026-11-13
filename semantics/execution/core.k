requires "runtime.k"

// The core accepts decoded input; the integrated frontend supplies pure initialization equations.
module DWARF-STATE
  imports DWARF-RUNTIME
  imports K-EQUAL
  syntax Input ::= DecodedExpression
  syntax KItem ::= evaluate(DecodedExpression, Context, Int, Purpose) [symbol(evaluation)]
                 | finished(DecodedExpression, Context, Int, EvaluationResult, Purpose) [symbol(finishedEvaluation)]
  syntax KItem ::= initialControl(Input, Context, Purpose) [function]
  rule initialControl(E:DecodedExpression, C, PURPOSE) => evaluate(E, C, inputEnd(E), PURPOSE)
  syntax Int ::= initialPosition(Input) [function]
  rule initialPosition(E:DecodedExpression) => inputStart(E)
  configuration
    <dwarf>
      <expr maincell=""> initialControl($PGM:Input, $CONTEXT:Context, $PURPOSE:Purpose) </expr>
      <pc> initialPosition($PGM:Input) </pc>
      <stack> $STACK:Stack </stack>
      <fragments> fragments(initialPosition($PGM:Input), noLocation, .Pieces,
                            objectBits(0, 0, 0), $STACK:Stack ==K .Stack) </fragments>
    </dwarf>
endmodule

// Independent execution rules do not import source syntax, decoding, or normalization.
module DWARF-EXECUTION
  imports DWARF-STATE
  // Failed preconditions leave the configuration unchanged, including nested return state. Stuckness alone
  // does not establish invalid DWARF.

  // Call and entry transitions count toward the rewrite budget; ordinary operations take one rewrite.
  syntax KItem ::= returnCall(DecodedExpression, Context, Int, Int, Int, Purpose, FragmentState) [symbol(returnCall)]
                 | returnEntry(DecodedExpression, Context, Int, Int, Int, Purpose, FragmentState, Stack) [symbol(returnEntry)]

  // Calls share the operand stack. A known DIE with an empty or absent location is a no-op; an unknown DIE
  // has no transition.
  rule [Call]:
       <expr> evaluate(E, C, END, PURPOSE) =>
         evaluate(dieCode(operationDIE(E, P, C)), dieContext(C, operationDIE(E, P, C)),
                  inputEnd(dieCode(operationDIE(E, P, C))), procedurePurpose)
         ~> returnCall(E, C, END, P, next(E, P), PURPOSE, F) ... </expr>
       <pc> P => 0 </pc>
       <fragments> F => fragments(0, noLocation, .Pieces, objectBits(0, 0, 0), true) </fragments>
       requires P <Int END andBool isCall(opAt(E, P))
         andBool hasDIE(lookupDIE(runtimeTable(C, "dies"), referencedDIE(opAt(E, P), C)))

  // Return restores the caller position and retains the shared stack.
  rule [ReturnCall]:
       <expr> evaluate(_, _, END, procedurePurpose) ~> returnCall(E, C, ROOTEND, _, NEXT, PURPOSE, F)
           => evaluate(E, C, ROOTEND, PURPOSE) ... </expr>
       <pc> END => NEXT </pc>
       <fragments> _ => F </fragments>

  // Entry expressions use an empty stack and an independent entry snapshot; missing inputs remain unknown.
  rule [Entry]:
       <expr> evaluate(E, C, END, PURPOSE) =>
         (#let entryValueOp(B) = opAt(E, P)
          #in evaluate(B, getContext(entryContext(C)), inputEnd(B), entryPurpose))
         ~> returnEntry(E, C, END, P, next(E, P), PURPOSE, F, S) ... </expr>
       <pc> P => 0 </pc>
       <stack> S => .Stack </stack>
       <fragments> F => fragments(0, noLocation, .Pieces, objectBits(0, 0, 0), true) </fragments>
       requires P <Int END andBool (entryValueOp(_) :=K opAt(E, P)) andBool hasContext(entryContext(C))

  // An ordinary entry expression must leave exactly one value; a standalone register description separately reads the entry register.
  rule [ReturnEntry]:
       <expr> evaluate(_, _, END, entryPurpose) ~> returnEntry(E, C, ROOTEND, _, NEXT, PURPOSE, F, S)
           => evaluate(E, C, ROOTEND, PURPOSE) ... </expr>
       <pc> END => NEXT </pc>
       <stack> push(.Stack, V) => push(S, V) </stack>
       <fragments> _ => F </fragments>

  rule [EntryRegister]:
       <expr> evaluate(E0, (ctx(A, _, _, RS, _, _, _, _, _, _, _) #as C0), END, entryPurpose)
          ~> returnEntry(E, C, ROOTEND, _, NEXT, PURPOSE, F, S) => evaluate(E, C, ROOTEND, PURPOSE) ... </expr>
       <pc> 0 => NEXT </pc>
       <stack> .Stack => (#let regxOp(R) = opAt(E0, 0) #in push(S, val(bits(getInt(lookupInt(RS, R)), A), g))) </stack>
       <fragments> _ => F </fragments>
       requires (regxOp(_) :=K opAt(E0, 0)) andBool next(E0, 0) ==Int END
         andBool (#let regxOp(R) = opAt(E0, 0) #in hasInt(lookupInt(RS, R)))

  // TLS translation is supplied for the current module and thread.
  rule [TLS]:
       <expr> evaluate(E, C, END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(OFFSET, T)) => push(S, val(getInt(lookupInt(runtimeTable(C, "tls"), OFFSET)), g)) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool opAt(E, P) ==K formTlsAddressOp
         andBool integerType(T) andBool hasInt(lookupInt(runtimeTable(C, "tls"), OFFSET))

  // Address-space reads take integral ADDR from the top and SPACE from below.
  rule [XDeref]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _, _, _, _, _) #as C), END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> push(push(S, val(SPACE, TS)), val(ADDR, TA)) =>
         (#let xderefOp(SIZE) = opAt(E, P) #in push(S, val(getInt(readAddressSpace(C, SPACE, SIZE, ADDR)), g))) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool (xderefOp(_) :=K opAt(E, P))
         andBool integerType(TS) andBool integerType(TA)
         andBool (#let xderefOp(SIZE) = opAt(E, P) #in validReadSize(SIZE, g, A) andBool hasInt(readAddressSpace(C, SPACE, SIZE, ADDR)))

  // XDerefType reads [SPACE,ADDR] into the requested type, which may be wider than the address.
  rule [XDerefType]:
       <expr> evaluate(E, (ctx(A, _, TYPES, _, _, _, _, _, _, _, _) #as C), END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> push(push(S, val(SPACE, TS)), val(ADDR, TA)) =>
         (#let xderefTypeOp(SIZE, REF) = opAt(E, P)
          #in push(S, getValue(interpretRead(readAddressSpace(C, SPACE, SIZE, ADDR), getType(lookupType(TYPES, REF)))))) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool (xderefTypeOp(_, _) :=K opAt(E, P))
         andBool integerType(TS) andBool integerType(TA)
         andBool (#let xderefTypeOp(SIZE, REF) = opAt(E, P) #in hasType(lookupType(TYPES, REF))
           andBool validReadSize(SIZE, getType(lookupType(TYPES, REF)), A) andBool hasInt(readAddressSpace(C, SPACE, SIZE, ADDR)))

  // Implicit pointers retain the DIE identity and signed byte offset.
  rule [ImplicitPointer]:
       <expr> evaluate(E, C, END, locationPurpose) =>
         (#let implicitPointerOp(REF, OFF) = opAt(E, P)
          #in finished(E, C, END, implicitPointer(REF, OFF), locationPurpose)) ... </expr>
       <pc> P => END </pc>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       requires P ==Int inputStart(E) andBool P <Int END
         andBool (implicitPointerOp(_, _) :=K opAt(E, P)) andBool next(E, P) ==Int END
         andBool (#let implicitPointerOp(REF, _) = opAt(E, P) #in hasDIE(lookupDIE(runtimeTable(C, "dies"), REF)))

  // Constants keep the low A bits as generic values; source operand ranges are checked during
  // normalization.
  rule [Const]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let constOp(N) = opAt(E, P)
                         #in push(S, val(bits(N, A), g))) </stack>
       requires P <Int END andBool (constOp(_) :=K opAt(E, P))

  // Typed constants use the CU base type and its exact storage size, in target byte order.
  rule [TypedConstant]:
       <expr> evaluate(E, (ctx(_, ORDER, TS, _, _, _, _, _, _, _, _) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let constTypeOp(REF, B) = opAt(E, P)
         #in push(S, getValue(constantValue(B, ORDER, lookupType(TS, REF))))) </stack>
       requires P <Int END andBool (constTypeOp(_, _) :=K opAt(E, P))
         andBool (#let constTypeOp(REF, B) = opAt(E, P)
           #in hasValue(constantValue(B, ORDER, lookupType(TS, REF))))

  // Typed registers read the low effective bits of register contents using the requested type encoding.
  rule [TypedRegister]:
       <expr> evaluate(E, (ctx(A, _, TS, RS, _, _, _, _, _, _, _) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let regvalTypeOp(R, REF) = opAt(E, P)
         #in push(S, getValue(registerTypedValue(lookupInt(RS, R), lookupType(TS, REF), physicalRegisterWidth(RS, R, A))))) </stack>
       requires P <Int END andBool (regvalTypeOp(_, _) :=K opAt(E, P))
         andBool (#let regvalTypeOp(R, REF) = opAt(E, P)
           #in hasValue(registerTypedValue(lookupInt(RS, R), lookupType(TS, REF), physicalRegisterWidth(RS, R, A))))

  // addrx adds the supplied load bias; constx keeps the table entry unchanged.
  rule [AddrIndex]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _, _, DA, BIAS, _) #as C), END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let addrxOp(I) = opAt(E, P)
          #in push(S, val(bits(getInt(lookupInt(DA, I)) +Int BIAS, A), g))) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool (addrxOp(_) :=K opAt(E, P))
         andBool (#let addrxOp(I) = opAt(E, P) #in hasInt(lookupInt(DA, I)))

  rule [ConstIndex]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _, _, DA, _, _) #as C), END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let constxOp(I) = opAt(E, P)
          #in push(S, val(bits(getInt(lookupInt(DA, I)), A), g))) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool (constxOp(_) :=K opAt(E, P))
         andBool (#let constxOp(I) = opAt(E, P) #in hasInt(lookupInt(DA, I)))

  // Object address is supplied independently; zero is a known address.
  rule [ObjectAddress]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _, _, _, _, someInt(ADDR)) #as C), END, _:Purpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> S => push(S, val(ADDR, g)) </stack>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       requires P <Int END andBool opAt(E, P) ==K pushObjectAddressOp

  // Breg pushes (register contents + signed offset) modulo 2^A.
  rule [Breg]:
       <expr> evaluate(E, (ctx(A, _, _, RS, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let bregxOp(R, D) = opAt(E, P)
                         #in push(S, val(bits(getInt(lookupInt(RS, R)) +Int D, A), g))) </stack>
       requires P <Int END andBool (bregxOp(_, _) :=K opAt(E, P))
         andBool (#let bregxOp(R, _) = opAt(E, P) #in hasInt(lookupInt(RS, R)))

  // Fbreg uses a supplied unsigned A-bit frame base and wraps FB+D modulo 2^A.
  rule [Fbreg]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, someInt(FB), _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let fbregOp(D) = opAt(E, P)
                         #in push(S, val(bits(FB +Int D, A), g))) </stack>
       requires P <Int END andBool (fbregOp(_) :=K opAt(E, P))

  // CFA is an independent address-width input; neither SP nor frame base supplies a default.
  rule [CallFrameCFA]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, someInt(CFA), _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => push(S, val(CFA, g)) </stack>
       requires P <Int END andBool opAt(E, P) ==K callFrameCfaOp

  // Deref requires an integral address, enough known bytes, and a size within generic capacity (DWARF 5
  // Section 2.5.1.3).
  rule [Deref]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(ADDR, ADDRTYPE)) =>
                   (#let derefOp(SIZE) = opAt(E, P)
                      #in push(S, val(getInt(readMemory(C, SIZE, ADDR)), g))) </stack>
       requires P <Int END andBool integerType(ADDRTYPE) andBool (derefOp(_) :=K opAt(E, P))
         andBool (#let derefOp(SIZE) = opAt(E, P)
                     #in validReadSize(SIZE, g, A) andBool hasInt(readMemory(C, SIZE, ADDR)))

  // DerefType requires the exact type storage size and preserves the effective bits, encoding, and type
  // identity.
  rule [DerefType]:
       <expr> evaluate(E, (ctx(_, _, TS, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(ADDR, ADDRTYPE)) =>
                   (#let derefTypeOp(SIZE, REF) = opAt(E, P)
                      #in push(S, getValue(readTypedValue(C, SIZE, lookupType(TS, REF), ADDR)))) </stack>
       requires P <Int END andBool integerType(ADDRTYPE) andBool (derefTypeOp(_, _) :=K opAt(E, P))
         andBool (#let derefTypeOp(SIZE, REF) = opAt(E, P)
                     #in hasValue(readTypedValue(C, SIZE, lookupType(TS, REF), ADDR)))

  // Pick copies a complete value by depth from the top. dup/over use depths 0/1; missing entries have no
  // transition.
  rule [Pick]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> S => (#let pickOp(K) = opAt(E, P)
                         #in push(S, getValue(stackAt(S, K)))) </stack>
       requires P <Int END andBool (pickOp(_) :=K opAt(E, P))
         andBool (#let pickOp(K) = opAt(E, P)
                     #in 0 <=Int K andBool K <=Int 255 andBool hasValue(stackAt(S, K)))

  rule [Drop]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, _) => S </stack>
       requires P <Int END andBool opAt(E, P) ==K dropOp

  rule [Swap]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(push(S, V2), V1) => push(push(S, V1), V2) </stack>
       requires P <Int END andBool opAt(E, P) ==K swapOp

  // Rot changes bottom-to-top [a,b,c] to [c,a,b], preserving complete values.
  rule [Rot]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(push(push(S, V3), V2), V1) => push(push(push(S, V1), V3), V2) </stack>
       requires P <Int END andBool opAt(E, P) ==K rotOp

  // Unary calculations preserve the operand type.
  rule [Unary]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(N, T)) =>
         (#let unaryOp(U) = opAt(E, P)
            #in push(S, val(getInt(uop(U, N, T, A)), T))) </stack>
       requires P <Int END andBool (unaryOp(_) :=K opAt(E, P))
         andBool (#let unaryOp(U) = opAt(E, P) #in hasInt(uop(U, N, T, A)))

  // Binary operands must have identical types. With N1 on top, compute N2 OP N1 and preserve the type.
  rule [Binary]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(push(S, val(N2, T)), val(N1, T)) =>
         (#let binaryOp(B) = opAt(E, P)
            #in push(S, val(getInt(bop(B, N1, N2, T, A)), T))) </stack>
       requires P <Int END andBool (binaryOp(_) :=K opAt(E, P))
         andBool (#let binaryOp(B) = opAt(E, P) #in hasInt(bop(B, N1, N2, T, A)))

  // Comparisons require identical operand types and return 0:g or 1:g; generic comparisons use a signed
  // view.
  rule [Compare]:
       <expr> evaluate(E, (ctx(A, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(push(S, val(N2, T)), val(N1, T)) =>
         (#let compareOp(CMP) = opAt(E, P)
            #in push(S, val(getInt(cmp(CMP, N1, N2, T, A)), g))) </stack>
       requires P <Int END andBool (compareOp(_) :=K opAt(E, P))
         andBool (#let compareOp(CMP) = opAt(E, P) #in hasInt(cmp(CMP, N1, N2, T, A)))

  // Conversion interprets the source at its own width. Boolean targets normalize to 0/1; other integers
  // keep target low bits. Boolean/float conversion is unsupported.
  rule [Convert]:
       <expr> evaluate(E, (ctx(A, _, TS, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(N, SOURCE)) =>
         (#let convertOp(REF) = opAt(E, P)
            #in push(S, val(getInt(convert(N, SOURCE, resolveType(TS, REF), A)),
                            getType(resolveType(TS, REF))))) </stack>
       requires P <Int END andBool (convertOp(_) :=K opAt(E, P))
         andBool (#let convertOp(REF) = opAt(E, P)
                     #in hasInt(convert(N, SOURCE, resolveType(TS, REF), A)))

  // Reinterpretation requires equal effective widths and preserves the low-bit pattern.
  rule [Reinterpret]:
       <expr> evaluate(E, (ctx(A, _, TS, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(N, SOURCE)) =>
         (#let reinterpretOp(REF) = opAt(E, P)
            #in push(S, val(getInt(reinterpret(N, SOURCE, resolveType(TS, REF), A)),
                            getType(resolveType(TS, REF))))) </stack>
       requires P <Int END andBool (reinterpretOp(_) :=K opAt(E, P))
         andBool (#let reinterpretOp(REF) = opAt(E, P)
                     #in hasInt(reinterpret(N, SOURCE, resolveType(TS, REF), A)))

  rule [Nop]:
       <expr> evaluate(E, C, END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       requires P <Int END andBool opAt(E, P) ==K nopOp

  // Skip targets NEXT+D without address-width wrapping. D is signed 16-bit; END and decoded boundaries are
  // valid targets, including backward jumps.
  rule [Skip]:
       <expr> evaluate(E, C, END, _:Purpose) ... </expr>
       <fragments> fragments(START, noLocation, _, _, _) </fragments>
       <pc> P => (#let skipOp(D) = opAt(E, P)
                      #in next(E, P) +Int D) </pc>
       requires P <Int END andBool (skipOp(_) :=K opAt(E, P))
         andBool (#let skipOp(D) = opAt(E, P)
                      #in localBoundary(E, START, next(E, P) +Int D))

  // A nonzero condition branches to a valid boundary or END, consuming the condition only on success.
  rule [BraTrue]:
       <expr> evaluate(E, C, END, _:Purpose) ... </expr>
       <fragments> fragments(START, noLocation, _, _, _) </fragments>
       <pc> P => (#let braOp(D) = opAt(E, P)
                      #in next(E, P) +Int D) </pc>
       <stack> push(S, val(N, _)) => S </stack>
       requires P <Int END andBool N =/=Int 0 andBool (braOp(_) :=K opAt(E, P))
         andBool (#let braOp(D) = opAt(E, P)
                      #in localBoundary(E, START, next(E, P) +Int D))

  // A zero condition falls through to NEXT; the untaken target need not be a valid boundary.
  rule [BraFalse]:
       <expr> evaluate(E, C, END, _:Purpose) ... </expr>
       <fragments> fragments(_, noLocation, _, _, _) </fragments>
       <pc> P => next(E, P) </pc>
       <stack> push(S, val(0, _)) => S </stack>
       requires P <Int END andBool (braOp(_) :=K opAt(E, P))

  // Value purpose returns the complete stack top, including an initial value on empty input; an empty
  // stack has no result.
  rule [Scalar]:
       <expr> evaluate(E, C, END, valuePurpose) => finished(E, C, END, scalarResult(V), valuePurpose) ... </expr>
       <pc> END </pc>
       <stack> push(_, V) </stack>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>

  // An empty location expression returns unavailable and preserves its initial stack.
  rule [Empty]:
       <expr> evaluate(E, C, END, locationPurpose) => finished(E, C, END, unavailable, locationPurpose) ... </expr>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       <pc> END </pc>
       requires emptyInput(E)

  // At END, a nonempty expression returns the top as a memory address without reading the object or
  // changing its representative. Completion requires a rewrite.
  rule [Memory]:
       <expr> evaluate(E, C, END, locationPurpose) => finished(E, C, END, memory(N), locationPurpose) ... </expr>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       <pc> END </pc>
       <stack> push(_, val(N, _)) </stack>
       requires notBool emptyInput(E)

  // DWARF 5 Section 2.6.1.1.3: reg must be the sole operation in its simple description; only its identity
  // is returned.
  rule [Register]:
       <expr> evaluate(E, C, END, locationPurpose)
           => (#let regxOp(R) = opAt(E, P)
                    #in finished(E, C, END, register(R), locationPurpose)) ... </expr>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       <pc> P => END </pc>
       requires P <Int END andBool P ==Int inputStart(E)
         andBool (regxOp(_) :=K opAt(E, P))
         andBool next(E, P) ==Int END

  // stack_value requires a nonempty stack and must end the description or immediately precede a piece.
  rule [StackValue]:
       <expr> evaluate(E, (ctx(_, _, _, _, _, _, _:OptionalInt, _:Architecture, _:Map, _:Int, _:OptionalInt) #as C), END, locationPurpose)
           => finished(E, C, END, value(V), locationPurpose) ... </expr>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       <pc> P => END </pc>
       <stack> push(_, V) </stack>
       requires P <Int END andBool instructionAt(E, P) ==K instruction(stackValueOp, END)

  // ImplicitValue returns the supplied bytes and preserves the initial stack.
  rule [ImplicitValue]:
       <expr> evaluate(E, C, END, locationPurpose)
         => (#let implicitValueOp(B) = opAt(E, P)
                   #in finished(E, C, END, bytesValue(B), locationPurpose)) ... </expr>
       <pc> P => END </pc>
       <fragments> fragments(_, noLocation, .Pieces, _, _) </fragments>
       requires P ==Int inputStart(E) andBool P <Int END
         andBool (implicitValueOp(_) :=K opAt(E, P))
         andBool next(E, P) ==Int END

  // A register or implicit-value fragment must be standalone before its delimiter; the piece then commits
  // and clears the stack.
  rule [PieceRegister]:
       <expr> evaluate(E, C, END, locationPurpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <fragments> fragments(P, noLocation, PS, BITS, true)
         => (#let regxOp(R) = opAt(E, P)
              #in fragments(P, located(register(R)), PS, BITS, true)) </fragments>
       requires P <Int END andBool (regxOp(_) :=K opAt(E, P))
         andBool followsComposition(E, next(E, P))

  rule [PieceImplicitValue]:
       <expr> evaluate(E, C, END, locationPurpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <fragments> fragments(P, noLocation, PS, BITS, true)
         => (#let implicitValueOp(B) = opAt(E, P)
              #in fragments(P, located(bytesValue(B)), PS, BITS, true)) </fragments>
       requires P <Int END andBool (implicitValueOp(_) :=K opAt(E, P))
         andBool followsComposition(E, next(E, P))

  // A fragment's stack_value must immediately precede its piece delimiter.
  rule [PieceStackValue]:
       <expr> evaluate(E, C, END, locationPurpose) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> push(_, V) </stack>
       <fragments> fragments(START, noLocation, PS, BITS, true)
          => fragments(START, located(value(V)), PS, BITS, true) </fragments>
       requires P <Int END andBool opAt(E, P) ==K stackValueOp
         andBool followsComposition(E, next(E, P))

  // A piece commits and clears the stack. Insufficient source width stops execution; missing data produce
  // unknown bits. A final delimiter completes; trailing fragments need a delimiter.
  syntax KItem ::= afterPiece(DecodedExpression, Context, Int, Int, Pieces, ObjectBits) [function]
  rule afterPiece(E, C, END, END, PS, BITS) => finished(E, C, END, assembledLocation(PS, BITS), locationPurpose)
  rule afterPiece(E, C, END, NEXT, _, _) => evaluate(E, C, END, locationPurpose) requires NEXT =/=Int END
  rule [ComposePiece]:
       <expr> evaluate(E, C, END, locationPurpose)
          => afterPiece(E, C, END, next(E, P),
               appendPiece(PS, pieceDesc(opAt(E, P), getLocation(fragmentLocation(P, START, L, S)))),
               appendBits(BITS, getBits(extractObject(getLocation(fragmentLocation(P, START, L, S)),
                    pieceSize(opAt(E, P)), pieceOffset(opAt(E, P)), C)))) ... </expr>
       <pc> P => next(E, P) </pc>
       <stack> S => .Stack </stack>
       <fragments> fragments(START, L, PS, BITS, true)
          => fragments(next(E, P), noLocation,
               appendPiece(PS, pieceDesc(opAt(E, P), getLocation(fragmentLocation(P, START, L, S)))),
               appendBits(BITS, getBits(extractObject(getLocation(fragmentLocation(P, START, L, S)),
                    pieceSize(opAt(E, P)), pieceOffset(opAt(E, P)), C))), true) </fragments>
       requires canCompose(P <Int END andBool isComposition(opAt(E, P)),
         opAt(E, P), P, START, L, S, C)
endmodule


module DWARF-CORE
  imports DWARF-EXECUTION
endmodule
