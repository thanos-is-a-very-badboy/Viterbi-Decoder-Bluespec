package Viterbi_v1;
import fp_adder::*;
import Vector::*;

interface Ifc_Viterbi;

    // --- Setup and state loading ---
    method ActionValue#(Bool) get_n_and_m_loaded();
    method Action n_and_m_load(Bit#(32) n, Bit#(32) m ,Bit#(32)outcome1);


    // --- Transition / Emission / Outcome data ---
    method Bit#(32) read_transition_idx();
    method Bit#(32) read_emission_idx();
    method Bit#(32) read_outcome_idx();

    method Action send_transition_data(Bit#(32) data);
    method Action send_emission_data(Bit#(32) data);
    method Action send_outcome_data(Bit#(32) data);

    // --- Optional: read enables (if your TB checks these flags) ---
    method Bool get_read_transition();
    method Action set_read_transition(Bool val);
    method Bool get_read_emission();
    method Bool get_read_outcome();

endinterface


(* synthesize *)
module mkViterbi(Ifc_Viterbi);

    Ifc_FP32_Adder adder <- mkFP32_Adder(); // internal FP adder

    Reg#(Bit#(32)) n_reg <- mkReg(0);
    Reg#(Bit#(32)) m_reg <- mkReg(0);
    Reg#(Bit#(32)) i_ctr <- mkReg(0);
    Reg#(Bit#(32)) j_ctr <- mkReg(0);
    Reg#(Bit#(32)) t_ctr <- mkReg(0);
    Reg#(Bit#(32)) input_idx_ctr <- mkReg(0);
    Reg#(Bit#(32)) outcome_reg <- mkReg(0);

    Reg#(Bit#(32)) transition_buffer <- mkReg(0);
    Reg#(Bit#(32)) emission_buffer <- mkReg(0);
    Reg#(Bit#(32)) outcome_buffer <- mkReg(0);

    Reg#(Bit#(32)) transition_idx <- mkReg(0);
    Reg#(Bit#(32)) emission_idx <- mkReg(0);
    Reg#(Bit#(32)) outcome_idx <- mkReg(0);

    // prev and curr state vectors
    Vector#(32, Reg#(Bit#(32))) prev <- replicateM(mkReg(32'h0));
    Vector#(32, Reg#(Bit#(32))) curr <- replicateM(mkReg(32'h0));

    // status flags 
    Reg#(Bool) read_transition <- mkReg(False);
    Reg#(Bool) read_emission <- mkReg(False);
    Reg#(Bool) read_outcome <- mkReg(False);
    Reg#(Bool) n_and_m_loaded <- mkReg(False);

    Reg#(Bool) transition_ready <- mkReg(False);
    Reg#(Bool) emission_ready <- mkReg(False);

    Reg#(Bool) init_in_progress <- mkReg(False);
    Reg#(Bool) init_done_flag <- mkReg(False);               
   
    // --- rules ---

    rule init_v(t_ctr==0 && !init_done_flag && n_and_m_loaded);
        //  want to read memory so issue request
        if(!transition_ready &&!read_transition)begin
            read_transition<=True;
            // read_emission<=True;
            // $display("asdfadsI: %d, P : %h", i_ctr, prev[i_ctr]);

            transition_idx<=i_ctr;
            emission_idx<=i_ctr*m_reg + outcome_reg;
        end
        else if(transition_ready)begin
            // can do addition
            let data = transition_buffer;
            prev[i_ctr]<=data;
            // $display("NYEGA, %d", i_ctr);

            
            read_transition<=False;
            // read_emission<=False;
            transition_ready<=False;

            if(i_ctr<n_reg-1)begin
                i_ctr<=i_ctr+1;
                // $display("VALUE of I : %d",i_ctr);
            end
            else begin
                i_ctr<=0;
                init_done_flag<=True;
                t_ctr<=t_ctr+1;
            end
        end
    endrule 

    // rule intit_v_iter(!init_done_flag && n_and_m_loaded);
    //     read_transition<=True;
    //     transition_idx<=i_ctr;
    // endrule 

    // rule init_v_iter_2(!init_done_flag && transition_ready);
    //     Bit#(32) data = transition_buffer;
    //     prev[i_ctr] <= data;
    //     transition_ready<=False;
    //     i_ctr <= i_ctr + 1;
    //     if(i_ctr==n_reg-1)begin
    //         init_done_flag<=True;
    //         read_transition<=False;
    //     end
    // endrule
    //     // Load transition data into internal structures
    
    rule done_init (init_done_flag);
        $display("Viterbi Initialization completed.");
        $display("N and M = %d, %d", n_reg, m_reg);

        for (Integer i = 0; fromInteger(i) < 8; i = i + 1) begin
            $display("I: %d, P : %h", i, prev[i]);
        end

        $finish(0);
    endrule


    // --- methods ---

    method ActionValue#(Bool) get_n_and_m_loaded();
        // read_transition<=True;
        // read_emission<=True;
        return n_and_m_loaded;
    endmethod 

    method Action n_and_m_load(Bit#(32) n, Bit#(32) m,Bit#(32)outcome1);
        n_reg <= n;
        m_reg <= m;
        outcome_reg<=outcome1;
        n_and_m_loaded <= True;
    endmethod

    method Action send_transition_data(Bit#(32) data);
        transition_buffer <= data;
        transition_ready <= True;
        read_transition<=False;
    endmethod

    method Action send_emission_data(Bit#(32) data);
        emission_buffer <= data;
        emission_ready <= True;
        read_emission <= False;
    endmethod

    method Action send_outcome_data(Bit#(32) data);
        outcome_buffer <= data;
    endmethod

    method Bit#(32) read_transition_idx();
        return transition_idx;
    endmethod

    method Bit#(32) read_emission_idx();
        return emission_idx;
    endmethod

    method Bit#(32) read_outcome_idx();
        return outcome_idx;
    endmethod

    method Bool get_read_transition();
        return read_transition;
    endmethod

    method Action set_read_transition(Bool val);
        read_transition <= val;
    endmethod

    method Bool get_read_emission();
        return read_emission;
    endmethod

    method Bool get_read_outcome();
        return read_outcome;
    endmethod

endmodule : mkViterbi
endpackage : Viterbi_v1
