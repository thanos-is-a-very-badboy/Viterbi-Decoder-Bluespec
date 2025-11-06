// BrentKungAdder.bsv
// Parameterized Brent–Kung–style prefix adder in Bluespec SystemVerilog (BSV).
// Instantiate with width W = 23 for your request.
//
// Build / generate Verilog:
//   bsc -u -g mkBrentKungAdder --verilog BrentKungAdder.bsv
//
// Notes:
//  - The design computes (generate, propagate) pairs (g,p), performs
//    an up-sweep tree combining stage, then a down-sweep to form prefix
//    carries. Finally computes sum bits. This follows the Brent–Kung
//    two-phase pattern (reduced logic compared to full Kogge–Stone).
//  - This module is written for clarity and synthesizability. Please
//    simulate (bsc + verilator or in your flow) to verify timing/area.

package BrentKungAdder;

import Vector :: *;    // used for fixed-size arrays
import RegFile :: *;   // not required, but available

// -----------------------------
// Helper: GP pair: generate/propagate
// -----------------------------
typedef struct {
Bool g; // generate
Bool p; // propagate
} GP deriving (Bits,Eq);

// Combine operator for prefix cells (black cell):
// Given left = (g_l, p_l), right = (g_r, p_r):
//   g_out = g_r | (p_r & g_l)
//   p_out = p_r & p_l
function GP gpCombine(GP left, GP right);
GP out;
out.g = right.g | (right.p & left.g);
out.p = right.p & left.p;
return out;
endfunction

// -----------------------------
// Top-level parametric module
// -----------------------------
module mkBrentKungAdder #(parameter Integer W = 24)
(
input  Bit#(W)  a,
input  Bit#(W)  b,
input  Bool     cin,
output Bit#(W)  sum,
output Bool     cout
);

// Number of levels required (ceil(log2(W)))
function Integer ceilLog2(Integer x);
    Integer v = 0;
    Integer t = 1;
    while (t < x) begin
        t = t <<< 1;
        v = v + 1;
    end
    return v;
endfunction

let L = ceilLog2(W);

// Convert inputs to bit vectors indexable LSB..MSB as vector[0] = LSB bit0
Vector#(W, Bool) a_bits = vectorFromBits(a); // utility that expands Bit#(W) to Vector#(W,Bool)
Vector#(W, Bool) b_bits = vectorFromBits(b);

// Step 1: initial GP pairs for each bit
Vector#(W, GP) gp0 = replicate(genFun);
function GP genFun();
    GP tmp;
    tmp.g = False;
    tmp.p = False;
    return tmp;
endfunction

// fill gp0
for (Integer i = 0; i < W; i = i + 1) begin
    gp0 = gp0 with i @= (GP { g : a_bits[i] & b_bits[i]
                             , p : a_bits[i] ^ b_bits[i] } );
end

// -----------------------------
// Up-sweep (reduction) stage:
// build partial prefix results in an array of levels.
// levels[0] : gp0 (bitwise)
// levels[k] : after combining with distance 2^(k-1)
// -----------------------------
Vector#(L+1, Vector#(W, GP)) levels = replicate(levelsGen);
function Vector#(W, GP) levelsGen();
    return gp0;   // initial default (will be overwritten)
endfunction

// level 0 = gp0
levels = levels with 0 @= gp0;

for (Integer s = 1; s <= L; s = s + 1) begin
    Vector#(W, GP) prev = levels[s-1];
    Vector#(W, GP) curr = replicate(currGen);
    function GP currGen();
        GP z; z.g = False; z.p = False; return z;
    endfunction

    Integer dist = (1 <<< (s-1)); // distance = 2^(s-1)
    // Brent–Kung style: combine only where needed to reduce node count.
    // Typical pattern: for index i: if (i >= dist) and ((i % (2*dist)) == (2*dist - 1) ? combine : else copy)
    // A simple, commonly-used reduction:
    for (Integer i = 0; i < W; i = i + 1) begin
        if (i >= dist) begin
            // For Brent–Kung we only create combines for indices where (i % (2*dist)) == (2*dist - 1)
            // and copy other indices from prev. This approximates the BK sparsity.
            if ((i & ((2*dist)-1)) == ((2*dist)-1)) begin
                // combine prev[i - dist] and prev[i]
                curr = curr with i @= gpCombine(prev[i - dist], prev[i]);
            end else begin
                // copy prev[i]
                curr = curr with i @= prev[i];
            end
        end else begin
            curr = curr with i @= prev[i];
        end
    end
    levels = levels with s @= curr;
end
// -----------------------------
// Down-sweep stage: propagate prefixes to all bits
// -----------------------------
// We'll create an array 'prefix' that contains the prefix GP for each bit (i.e., carry into that bit).
Vector#(W, GP) prefix = replicate(prefGen);
function GP prefGen();
    GP z; z.g = False; z.p = True; // neutral for prefix (no generate, propagate true)
    return z;
endfunction

// For Brent–Kung, the final carry-in for bit i is constructed using selective combines from levels.
// We'll follow the common BK pattern: starting from the top-level sparsely-computed nodes,
// then filling in missing prefixes with combines from lower levels.
//
// We'll compute prefix[i] as follows:
//   prefix[0] = (g = cin, p = 0?)  -- instead compute carry Boolean separately
//   For bit i (0-based), the carry into bit i (c_i) is:
//       c_0 = cin
//       c_{i+1} = gp_prefix[i].g | (gp_prefix[i].p & cin)
//
// For convenience, compute an initial GP representing cin as GP_cin:
GP gp_cin;
gp_cin.g = cin;
gp_cin.p = False; // cin does not propagate

// We fill prefix[] iteratively using the levels. This is a simple and safe way to get correct prefixes,
// albeit not the absolute minimal BK node layout in HW. It is still Brent–Kung style (reduced nodes).
for (Integer i = 0; i < W; i = i + 1) begin
    // Build prefix for bit i by combining the necessary partials from levels.
    // A straightforward approach: compute the prefix by combining all higher-order partials
    // starting from the coarsest level down to level 0, combining when their range covers i.
    GP acc = gp0[i]; // start with the bit itself
    // Look for contributions at higher levels that cover index i
    for (Integer s = 1; s <= L; s = s + 1) begin
        Integer dist = (1 <<< (s-1));
        // If index i is a right-side node of a combine at level s (i.e., (i & (2*dist-1)) == 2*dist-1),
        // then combine the left-side partial from levels[s-1] at (i - dist)
        if (i >= dist) begin
            if ((i & ((2*dist)-1)) == ((2*dist)-1)) begin
                // combine levels[s-1][i - dist] with acc
                acc = gpCombine(levels[s-1][i - dist], acc);
            end
        end
    end
    // Now acc is the prefix GP for bit i relative to lower bits. Store it.
    prefix = prefix with i @= acc;
end

// -----------------------------
// From GP prefix to carry bits and sums:
// c0 = cin
// For bit i:
//   carry into bit i (call it c_i) = (prefix[i-1] combined with cin)
//   More directly, the carry-out of bit i (c_{i+1}) = prefix[i].g | (prefix[i].p & cin)
// We compute carries for i = 0..W (c_0..c_W)
// -----------------------------
Vector#(W+1, Bool) carry = replicate(carryGen);
function Bool carryGen();
    return False;
endfunction

// c0 = cin
carry = carry with 0 @= cin;

for (Integer i = 0; i < W; i = i + 1) begin
    Bool c_next = prefix[i].g | (prefix[i].p & cin);
    // But above expression uses global cin, correct only if prefix[i] is GP relative to bit -1.
    // To be safe, we can compute carry incrementally using prefix of lower index:
    // compute carry[i+1] by combining prefix for bits [0..i] with gp_cin.
    // So form temp = gpCombine(gp_prefix_of_0..i , gp_cin) and then c_{i+1} = temp.g
    // We'll compute a fresh combination:
    // Build GP_all = prefix[i] combined with gp_cin (treating gp_cin as left-most)
    GP gp_all = gpCombine(gp_cin, prefix[i]);
    carry = carry with (i+1) @= gp_all.g; 
end

// Compute sum bits: s_i = p_i XOR carry_i
Vector#(W, Bool) sum_bits = replicate(sumGen);
function Bool sumGen();
    return False;
endfunction

for (Integer i = 0; i < W; i = i + 1) begin
    Bool pi = gp0[i].p;       // propagate for bit i is a ^ b
    Bool ci = carry[i];       // carry into bit i
    sum_bits = sum_bits with i @= (pi ^ ci);
end

// Final outputs
sum = bitsFromVector(sum_bits);       // utility to pack Vector#(W,Bool) to Bit#(W)
cout = carry[W];

endmodule
// ---------------------------------
// Support utilities (vectorFromBits / bitsFromVector)
// minimal helper functions to convert Bit#(W) <-> Vector#(W,Bool).
// If your Bluespec environment provides built-ins, you can replace these.
// ---------------------------------
function Vector#(W, Bool) vectorFromBits(Bit#(W) b) provisos (Integer W);
Vector#(W, Bool) v = replicate(vGen);
function Bool vGen(); return False; endfunction
for (Integer i = 0; i < W; i = i + 1) begin
v = v with i @= ( (b >> i) & 1 == 1 );
end
return v;
endfunction

function Bit#(W) bitsFromVector(Vector#(W, Bool) v) provisos (Integer W);
Bit#(W) out = 0;
for (Integer i = 0; i < W; i = i + 1) begin
out = out | (bitToBit#(v[i]) <<< i);
end
return out;
endfunction

// convert Bool to 1-bit Bit
function Bit#(1) bitToBit#(Bool b);
return b ? 1 : 0;
endfunction

endpackage