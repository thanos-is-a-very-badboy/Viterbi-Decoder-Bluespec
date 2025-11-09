package BK_Adder;

import Vector :: *;

// GP Pair
typedef struct {
  Bit#(1) g; // generate
  Bit#(1) p; // propagate
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
    Bit#(1)     cout;
} AdderResult24 deriving (Bits);


//Interface
interface BrentKungAdder24_IFC;
  method AdderResult24 calculate(Bit#(24) a, Bit#(24) b, Bit#(1) cin);
endinterface


// Initial Stage GP - fine
function Vector#(24, GP) calcInitialGP(Bit#(24) a, Bit#(24) b);
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
  out[0] = gpCombine(in[1], in[0]);
  return out;
endfunction


// Replaces C_calc (Unchanged)
function Bit#(25) calcCarries24(
    Bit#(1)            cin,
    Vector#(24, GP) gp0, // G, P (24 groups of 1)
    Vector#(12, GP) gp1, // G1, P1 (12 groups of 2)
    Vector#(6, GP)  gp2, // G2, P2 (6 groups of 4)
    Vector#(3, GP)  gp3, // G3, P3 (3 groups of 8)
    Vector#(1, GP)  gp4 // Only for 16
);
  
    Bit#(25) c = 0; // c[0]...c[23] are carries, c[24] is Cout

  function Bit#(1) carryOut(GP gp, Bit#(1) carry_in);
     return gp.g | (gp.p & carry_in);
  endfunction

  // --- Block 0 (Bits 0-7) ---> Correct
  c[0] = cin;
  c[1] = carryOut(gp0[0],  c[0]);
  c[2] = carryOut(gp1[0],  c[0]);
  c[3] = carryOut(gp0[2],  c[2]);
  c[4] = carryOut(gp2[0],  c[0]);
  c[5] = carryOut(gp0[4],  c[4]);
  c[6] = carryOut(gp1[2],  c[4]);
  c[7] = carryOut(gp0[6],  c[6]);
  
  // --- Block 1 (Bits 8-15) ---> Correct
  c[8] = carryOut(gp3[0],  c[0]); 
  c[9] = carryOut(gp0[8],  c[8]);
  c[10] = carryOut(gp1[4], c[8]);
  c[11] = carryOut(gp0[10], c[10]);
  c[12] = carryOut(gp2[2], c[8]);
  c[13] = carryOut(gp0[12], c[12]);
  c[14] = carryOut(gp1[6], c[12]);
  c[15] = carryOut(gp0[14], c[14]);
  
  // --- Block 2 (Bits 16-23) ---> Correct
  c[16] = carryOut(gp4[0], c[0]); 
  c[17] = carryOut(gp0[16], c[16]);
  c[18] = carryOut(gp1[8], c[16]);
  c[19] = carryOut(gp0[18], c[18]);
  c[20] = carryOut(gp2[4], c[16]);
  c[21] = carryOut(gp0[20], c[20]);
  c[22] = carryOut(gp1[10], c[20]);
  c[23] = carryOut(gp0[22], c[22]);

  // --- Final Cout ---> Fixed
  c[24] = carryOut(gp3[2], c[16]); 

  return c;
endfunction

// Replaces sum_calc (Unchanged)
function Bit#(24) calcSum(
    Vector#(24, GP)   gp0,   // Contains the initial P bits (A[i] ^ B[i])
    Bit#(24) c_in   // Contains C[0]...C[23]
);
    Bit#(24) s = 0;
  
    for (Integer i = 0; i < 24; i = i + 1) begin
        s[i] = gp0[i].p ^ c_in[i];
    end
    
    return s;
endfunction


// -------------------------------------------------------------------
// --- Top-Level Module (Modified to call new functions) ---
// -------------------------------------------------------------------
(* synthesize *)
module mkBrentKungAdder24(BrentKungAdder24_IFC);

  method AdderResult24 calculate(Bit#(24) a, Bit#(24) b, Bit#(1) cin);
      
      // Convert A and B to bit vectors
    //   Vector#(24, Bool) a_bits = vectorFromBits(a);
    //   Vector#(24, Bool) b_bits = vectorFromBits(b);
      
      // --- Step 1: Up-Sweep (Prefix Tree) ---
      
    //Initial GPs
    Vector#(24, GP) gp0 = calcInitialGP(a, b);
      
    //1st Level Merged GPs
    Vector#(12, GP) gp1 = mergeLevel_24_to_12(gp0);
      
    //2nd Level Merged GPs
    Vector#(6, GP) gp2 = mergeLevel_12_to_6(gp1);
      
    //3rd Level Merged GPs
    Vector#(3, GP) gp3 = mergeLevel_6_to_3(gp2);
      
    //4th Level Merged GPs
    Vector#(1, GP) gp4 = mergeLevel_2_to_1(cons(gp3[1], cons(gp3[0], nil))); 
      
    //Calculate Carries
    Bit#(25) all_carries = calcCarries24(cin, gp0, gp1, gp2, gp3, gp4);
    
    //Carry Out
    Bit#(1) cout = all_carries[24];

    //Calculate Final Sum
    Bit#(24) sum = calcSum(gp0, all_carries[23:0]);
      
    return AdderResult24 { sum: sum, cout: cout };
  endmethod

endmodule

endpackage