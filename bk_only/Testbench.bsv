package Testbench;

// Import your adder package
import BK_Adder :: *;
import Vector :: *;
// Import standard libraries
// import StdIO :: *;

// This module will be the top-level for simulation
module mkTestbench();

    // 1. Instantiate the Device Under Test (DUT)
    BrentKungAdder24_IFC adder <- mkBrentKungAdder24;
    
    // 2. State Register
    // This register acts as a clock cycle counter to sequence through tests
    Reg#(int) cycle <- mkReg(0);

    // 3. Main Test Rule
    // This rule fires once per clock cycle
    rule rl_test_sequence;
        
        // --- Define test vectors ---
        Bit#(24) a = 0;
        Bit#(24) b = 0;
        Bit#(1)  cin = 0; // Keep cin=0 as requested
        
        // --- ** MODIFIED TEST PATTERNS ** ---
        // Iterate through all 24 bits
        if (cycle < 24) begin
            // if(cycle == 7) begin
                a = (1 << cycle);
                b = (1 << cycle);
            // end
        end
        else begin
            // All tests are done (cycle 0 through 23)
            $display("\n----------------------------------------");
            $display(">>> SIMULATION PASSED <<<");
            $display("All test vectors correct.");
            $display("----------------------------------------\n");
            $finish; // End the simulation
        end
        // --- ** END OF MODIFICATIONS ** ---

        
        // --- Golden Model (Calculate the correct answer) ---
        
        // Extend inputs to 25 bits to capture the final carry-out
        Bit#(25) a_ext   = zeroExtend(a);
        Bit#(25) b_ext   = zeroExtend(b);
        Bit#(25) cin_ext = zeroExtend(cin);
        
        // Use BSV's built-in arithmetic as the "golden" reference
        Bit#(25) golden_result = a_ext + b_ext + cin_ext;
        
        // Extract the expected sum and cout from the golden result
        Bit#(24) expected_sum  = golden_result[23:0];
        Bit#(1)  expected_cout = golden_result[24];
        
        
        // --- Call the DUT ---
        // This is a combinational call; the result is available immediately
        AdderResult24 dut_result = adder.calculate(a, b, cin);
        

        // --- Check and Report ---
        if (dut_result.sum != expected_sum || dut_result.cout != expected_cout) begin
            // Failure
            $display("\n----------------------------------------");
            $display(">>> SIMULATION FAILED ON CYCLE %d (Testing Bit %d) <<<", cycle, cycle);
            $display("Inputs:  A = %h, B = %h, Cin = %b", a, b, cin);
            $display("Expected: Sum = %h, Cout = %b", expected_sum, expected_cout);
            $display("Got:      Sum = %h, Cout = %b", dut_result.sum, dut_result.cout);
            $display("Got:      Carries = %h ", dut_result.debug_carries);
            // $display("Got:      G = %b, P = %b", dut_result.gp_16th[0].p, dut_result.gp_16th[0].g );
            // for (Integer i = 0; i<24; i=i+1) begin
            //     $display("GP0[%d]: G:%b P:%b ", i, dut_result.gp0[i].g, dut_result.gp0[i].p);
            // end


            // $display("----------------------------------------\n");
            // for (Integer i = 0; i<12; i=i+1) begin
            //     $display("GP1[%d]: G:%b P:%b ", i, dut_result.gp1[i].g, dut_result.gp1[i].p);
            // end

            $display("----------------------------------------\n");

            for (Integer i = 0; i<6; i=i+1) begin
                $display("GP2[%d]: G:%b P:%b ", i, dut_result.gp2[i].g, dut_result.gp2[i].p);
            end

            $display("----------------------------------------\n");

            for (Integer i = 0; i<3; i=i+1) begin
                $display("GP3[%d]: G:%b P:%b ", i, dut_result.gp3[i].g, dut_result.gp3[i].p);
            end

            $display("----------------------------------------\n");

            for (Integer i = 0; i<1; i=i+1) begin
                $display("GP4[%d]: G:%b P:%b ", i, dut_result.gp4[i].g, dut_result.gp4[i].p);
            end

            $display("----------------------------------------\n");
            
            $finish; // Stop on failure
        end
        else begin
            // Success (for this cycle)
            $display("Cycle %d (Bit %d): PASSED | A: %h, B: %h, Cin: %b -> Sum: %h, Cout: %b",
                     cycle, cycle, a, b, cin, dut_result.sum, dut_result.cout);
        end
        
        // Advance to the next cycle/test case
        cycle <= cycle + 1;
        
    endrule

endmodule

endpackage