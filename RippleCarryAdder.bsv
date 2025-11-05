package RippleCarryAdder;
  import Prelude :: *;
  // Custom structs (remain the same)
  typedef struct{
    Bit#(24) inp1;
    Bit#(24) inp2;
  } AdderInput deriving(Bits, Eq);

  typedef struct{
    Bit#(1)  overflow;
    Bit#(24) sum;
  } AdderResult deriving(Bits, Eq);

// ------------------------------------------------------------------
// 1. INTERFACE DEFINITION
// ------------------------------------------------------------------
  interface RCA_ifc;
    // The method takes inputs and returns the result immediately (combinational)
    method AdderResult calculate(Bit#(24) a, Bit#(24) b);
  endinterface : RCA_ifc

// ------------------------------------------------------------------
// 2. TOP-LEVEL MODULE (mkCombinationalAdder)
// ------------------------------------------------------------------
  (*synthesize*)
  module mkRippleCarryAdder(RCA_ifc);
    
    // The core combinational logic function (remains the same)
    function AdderResult ripple_carry_addition (
      Bit#(24) a,
      Bit#(24) b,
      Bit#(1)  cin
    );
      Bit#(24) sum;
      Bit#(25) carry = '0;

      carry[0] = cin;

      for (Integer i = 0; i < 24; i = i + 1) begin
        sum  [i]   = (a[i] ^ b[i] ^ carry[i]);
        // Carry logic: (A&B) | (Cin & (A^B))
        carry[i+1] = (a[i] & b[i]) | (carry[i] & (a[i] ^ b[i]));
      end

      AdderResult out;
      out.sum      = sum;
      out.overflow = carry[24]; // Carry out of the last stage (C24)

      return out;
    endfunction : ripple_carry_addition

    // ------------------------------------------------------------------
    // 3. NEW INTERFACE METHOD DEFINITION
    // ------------------------------------------------------------------
    // Interface method definition: Directly calls the combinational function
    method AdderResult calculate(Bit#(24) a, Bit#(24) b);
      Bit#(1) cin = 0; // Assume carry-in is zero for simple addition
      return ripple_carry_addition(a, b, cin);
    endmethod : calculate

  endmodule : mkRippleCarryAdder

endpackage : RippleCarryAdder