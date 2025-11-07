package BK_Adder;

import Vector :: *;

// GP Pair
typedef struct {
  Bool g; // generate
  Bool p; // propagate
} GP deriving (Bits, Eq);


// Merge GP
function GP gpCombine(GP left, GP right);
  GP out;
  out.g = right.g | (right.p & left.g);
  out.p = right.p & left.p;
  return out;
endfunction

//Result
typedef struct {
    Bit#(24) sum;
    Bool     cout;
} AdderResult24 deriving (Bits);


//Interface
interface BrentKungAdder24_IFC;
  method AdderResult24 calculate(Bit#(24) a, Bit#(24) b, Bool cin);
endinterface


// Initial Stage GP - fine
function Vector#(24, GP) calcInitialGP(Vector#(24, Bool) a, Vector#(24, Bool) b);
  Vector#(24, GP) gp = newVector();
  for (Integer i = 0; i < 24; i = i + 1) begin
    gp[i] = GP { g: a[i] & b[i], p: a[i] ^ b[i] };
  end
  return gp;
endfunction

// First Level Merge - fine
function Vector#(12, GP) mergeLevel_24_to_12(Vector#(24, GP) in);
  Vector#(12, GP) out = newVector();
  for (Integer i = 0; i < 12; i = i + 1) begin
    out[i] = gpCombine(in[2*i], in[2*i + 1]);
  end
  return out;
endfunction

// Second Level Merge - fine
function Vector#(6, GP) mergeLevel_12_to_6(Vector#(12, GP) in);
  Vector#(6, GP) out = newVector();
  for (Integer i = 0; i < 6; i = i + 1) begin
    out[i] = gpCombine(in[2*i], in[2*i + 1]);
  end
  return out;
endfunction

// Third Merge Level - fine
function Vector#(3, GP) mergeLevel_6_to_3(Vector#(6, GP) in);
  Vector#(3, GP) out = newVector();
  for (Integer i = 0; i < 3; i = i + 1) begin
    out[i] = gpCombine(in[2*i], in[2*i + 1]);
  end
  return out;
endfunction

// Fourth Merge Level - fine
function Vector#(1, GP) mergeLevel_2_to_1(Vector#(2, GP) in);
  Vector#(1, GP) out = newVector();
  out[0] = gpCombine(in[0], in[1]);
  return out;
endfunction


// Replaces C_calc (Unchanged)
function Bit#(25) calcCarries24(
    Bit#(1)            cin,
    Vector#(24, GP) gp0, // G, P (24 groups of 1)
    Vector#(12, GP) gp1, // G1, P1 (12 groups of 2)
    Vector#(6, GP)  gp2, // G2, P2 (6 groups of 4)
    Vector#(3, GP)  gp3, // G3, P3 (3 groups of 8)
    Vector#(2, GP)  gp4, // G4, P4 (1 group of 16, 1 group of 8)
    GP              gp5  // G5, P5 (1 group of 24)
);
  
    Bit#(25) c = 0; // c[0]...c[23] are carries, c[24] is Cout

  function Bool carryOut(GP gp, Bool carry_in);
     return gp.g | (gp.p & carry_in);
  endfunction

  // --- Block 0 (Bits 0-7) ---
  c[0] = cin;
  c[1] = carryOut(gp0[0],  c[0]);
  c[2] = carryOut(gp1[0],  c[0]);
  c[3] = carryOut(gp0[2],  c[2]);
  c[4] = carryOut(gp2[0],  c[0]);
  c[5] = carryOut(gp0[4],  c[4]);
  c[6] = carryOut(gp1[2],  c[4]);
  c[7] = carryOut(gp0[6],  c[6]);
  
  // --- Block 1 (Bits 8-15) ---
  c[8] = carryOut(gp3[0],  c[0]); 
  c[9] = carryOut(gp0[8],  c[8]);
  c[10] = carryOut(gp1[4], c[8]);
  c[11] = carryOut(gp0[10], c[10]);
  c[12] = carryOut(gp2[2], c[8]);
  c[13] = carryOut(gp0[12], c[12]);
  c[14] = carryOut(gp1[6], c[12]);
  c[15] = carryOut(gp0[14], c[14]);
  
  // --- Block 2 (Bits 16-23) ---
  c[16] = carryOut(gp4[0], c[0]); 
  c[17] = carryOut(gp0[16], c[16]);
  c[18] = carryOut(gp1[8], c[16]);
  c[19] = carryOut(gp0[18], c[18]);
  c[20] = carryOut(gp2[4], c[16]);
  c[21] = carryOut(gp0[20], c[20]);
  c[22] = carryOut(gp1[10], c[20]);
  c[23] = carryOut(gp0[22], c[22]);

  // --- Final Cout ---
  c[24] = carryOut(gp5, c[0]); 

  return c;
endfunction

// Replaces sum_calc (Unchanged)
function Vector#(24, Bool) calcSum(
    Vector#(24, GP)   gp0,   // Contains the initial P bits (A[i] ^ B[i])
    Vector#(24, Bool) c_in   // Contains C[0]...C[23]
);
  Vector#(24, Bool) s = newVector();
  for (Integer i = 0; i < 24; i = i + 1) begin
    s[i] = gp0[i].p ^ c_in[i];
  end
  return s;
endfunction


// -------------------------------------------------------------------
// --- Top-Level Module (Modified to call new functions) ---
// -------------------------------------------------------------------

module mkBrentKungAdder24(BrentKungAdder24_IFC);

  method AdderResult24 calculate(Bit#(24) a, Bit#(24) b, Bool cin);
      
      // Convert A and B to bit vectors
      Vector#(24, Bool) a_bits = vectorFromBits(a);
      Vector#(24, Bool) b_bits = vectorFromBits(b);
      
      // --- Step 1: Up-Sweep (Prefix Tree) ---
      
      // 24 groups of 1-bit
      Vector#(24, GP) gp0 = calcInitialGP(a_bits, b_bits);
      
      // 12 groups of 2-bits
      Vector#(12, GP) gp1 = mergeLevel_24_to_12(gp0);
      
      // 6 groups of 4-bits
      Vector#(6, GP) gp2 = mergeLevel_12_to_6(gp1);
      
      // 3 groups of 8-bits (Groups 0-7, 8-15, 16-23)
      Vector#(3, GP) gp3 = mergeLevel_6_to_3(gp2);
      
      // Combine gp3[0] (0-7) and gp3[1] (8-15) -> 1 group of 16-bits
      // init(gp3) is Vector#(2, GP)
      Vector#(1, GP) gp4_temp = mergeLevel_2_to_1(init(gp3)); 
      
      // gp4[0] is (0-15), gp4[1] is (16-23)
      Vector#(2, GP) gp4 = cons(gp4_temp[0], cons(last(gp3), nil)); 
      
      // Combine gp4[0] (0-15) and gp4[1] (16-23) -> 1 group of 24-bits
      // gp4 is Vector#(2, GP)
      Vector#(1, GP) gp5_temp = mergeLevel_2_to_1(gp4);
      GP gp5 = gp5_temp[0]; // This is the final (0-23) GP group
      
      // --- Step 2: Down-Sweep (Carry Calculation) ---
      Vector#(25, Bool) all_carries = calcCarries24(cin, gp0, gp1, gp2, gp3, gp4, gp5);

      // Extract carries for sum (C[23:0])
    //   Vector#(24, Bool) sum_carries = newVector();
    //   for(Integer i=0; i<24; i=i+1) {
    //       sum_carries[i] = all_carries[i];
    //   }
      // Extract the final Cout (C[24])
      Bool cout = all_carries[24];

      // --- Step 3: Final Sum ---
      Vector#(24, Bool) sum_bits = calcSum(gp0, all_carries);
      
      Bit#(24) sum = bitsFromVector(sum_bits);
      
      return AdderResult24 { sum: sum, cout: cout };
  endmethod

endmodule

// -----------------------------
// Utility functions (Unchanged)
// -----------------------------
function Vector#(24, Bool) vectorFromBits(Bit#(24) b);
  Vector#(24, Bool) v = newVector();
  for (Integer i = 0; i < 24; i = i + 1)
    v[i] = ((b >> i) & 1) == 1;
  return v;
endfunction

function Bit#(1) bitToBit(Bool b);
  return b ? 1 : 0;
endfunction

function Bit#(24) bitsFromVector(Vector#(24, Bool) v);
  Bit#(24) out = 0;
  for (Integer i = 0; i < 24; i = i + 1)
    out = out | (bitToBit(v[i]) << i);
  return out;
endfunction

endpackage