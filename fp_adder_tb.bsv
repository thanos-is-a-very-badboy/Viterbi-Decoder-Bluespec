import fp_adder::*;

(* synthesize *)
module mkTestbench();

    Ifc_FP32_Adder adder <- mkFP32_Adder();

    Bit#(32) neg1 = 32'hfb710048; // -1.0
    Bit#(32) neg2 = 32'hfb7fc09f; // -1.46

    Reg#(Bit#(32)) res <- mkReg(0);

    // Step 1: start exponent matching
    Reg#(Bool) started <- mkReg(False);
    Reg#(Bool) completed <- mkReg(False);

    rule start_match (!started);
        adder.match_exponents(neg1, neg2);
        $display("Matching exponents...");
        started <= True;
    endrule

    // Step 2: wait for state_1_done
    rule add_mantissa (adder.state_1_done() && !adder.state_2_done());
        adder.add_mantissa();
        $display("Mantissas added");
    endrule

    // Step 3: wait for state_2_done
    rule normalize (adder.state_2_done() && !adder.state_3_done());
        adder.normalise();
        $display("Normalization done");
    endrule

    // Step 4: final output
    rule done (adder.state_3_done());
        res <= adder.get_res();
        completed <= True;
        $display("Computation completed.");
    endrule

    rule display (completed);
        $display("Result: %h", res);
        $finish(0);
    endrule

endmodule
