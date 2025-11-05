package RippleCarrySubtractor;
  import Prelude :: *;

  // ------------------------------------------------------------------
  // 1. STRUCT DEFINITIONS
  // ------------------------------------------------------------------
  typedef struct{
    Bit#(8) inp1;
    Bit#(8) inp2;
  } SubtractorInput deriving(Bits, Eq);

  typedef struct{
    Bit#(1)  borrow;   // Equivalent to "overflow" in adder
    Bit#(8)  diff;
  } SubtractorResult deriving(Bits, Eq);

  // ------------------------------------------------------------------
  // 2. INTERFACE DEFINITION
  // ------------------------------------------------------------------
  interface SUB_ifc;
    method SubtractorResult calculate(Bit#(8) a, Bit#(8) b);
  endinterface : SUB_ifc

  // ------------------------------------------------------------------
  // 3. TOP-LEVEL MODULE (mkRippleCarrySubtractor)
  // ------------------------------------------------------------------
  (* synthesize *)
  module mkRippleCarrySubtractor(SUB_ifc);

    // Core combinational logic: Ripple-Carry Subtractor
    function SubtractorResult ripple_carry_subtraction (
      Bit#(8) a,
      Bit#(8) b,
      Bit#(1) bin   // borrow in (usually 0)
    );
      Bit#(8) diff;
      Bit#(9) borrow = '0;

      borrow[0] = bin;

      for (Integer i = 0; i < 8; i = i + 1) begin
        // Difference bit: a[i] ^ b[i] ^ borrow[i]
        diff[i] = a[i] ^ b[i] ^ borrow[i];

        // Borrow logic: (~a & b) | (borrow & (~a ^ b))
        borrow[i+1] = ((~a[i]) & b[i]) | (borrow[i] & ((~a[i]) ^ b[i]));
      end

      SubtractorResult out;
      out.diff   = diff;
      out.borrow = borrow[8]; // Borrow out of MSB
      return out;
    endfunction : ripple_carry_subtraction

    // ------------------------------------------------------------------
    // 4. INTERFACE METHOD
    // ------------------------------------------------------------------
    method SubtractorResult calculate(Bit#(8) a, Bit#(8) b);
      Bit#(1) bin = 0; // No borrow-in for simple subtraction
      return ripple_carry_subtraction(a, b, bin);
    endmethod : calculate

  endmodule : mkRippleCarrySubtractor

endpackage : RippleCarrySubtractor
