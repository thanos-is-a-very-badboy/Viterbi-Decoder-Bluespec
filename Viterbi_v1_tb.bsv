import Viterbi_v1::*;
import RegFile::*;

(* synthesize *)
module mkViterbiTestbench();

    Ifc_Viterbi viterbi <- mkViterbi();

    RegFile#(Bit#(32), Bit#(32)) p_transition <- mkRegFileLoad("./Inputs/A_small.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) p_emission <- mkRegFileLoad("./Inputs/B_small.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) inputs <- mkRegFileLoad("./Inputs/input_small.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) n_and_m <- mkRegFileLoad("./Inputs/N_small.dat", 0, 1023);

    Bit#(32) n = n_and_m.sub(0);
    Bit#(32) m = n_and_m.sub(1);
    Bit#(32) outcome = inputs.sub(0);

    Reg#(Bool) read_transition_tb <- mkReg(False);
    Reg#(Bit#(32)) transition_idx_tb <- mkReg(32'h0);

    rule load_m_and_n;
        let loaded <- viterbi.get_n_and_m_loaded();
        if(!loaded)begin
            viterbi.n_and_m_load(n,m,outcome);
        end
    endrule

    rule read_66(viterbi.get_read_transition() && !read_transition_tb);
       read_transition_tb <= True;
       transition_idx_tb <= viterbi.read_transition_idx();
    //    $display("NYEGA123");
        // $display("Viterbi Initialization started with n=%0d, m=%0d, outcome=%0d", n, m, outcome);
    endrule

    rule read_transition_matrix(read_transition_tb == True);
        // if(viterbi.get_read_transition())begin
            
            // $display("I  = %d",transition_idx_tb);
            Bit#(32) data = p_transition.sub(transition_idx_tb);
            // Bit#(32) data = p_transition.sub(0);
            viterbi.send_transition_data(data);
            read_transition_tb <= False;
            // $display("NYEGA");
        // end
        // $display("Viterbi Initialization started with n=%0d, m=%0d, outcome=%0d", n, m, outcome);
    endrule

    
    // rule read_emission_matrix (viterbi.get_read_emission());
    //     let transition_idx = viterbi.read_emission_idx();
    //     Bit#(32) data = p_emission.sub(transition_idx);
    //     viterbi.send_emission_data(data);
    //     // $display("Viterbi Initialization started with n=%0d, m=%0d, outcome=%0d", n, m, outcome);
    // endrule

    
    // rule read_outcome_matrix (viterbi.get_read_outcome());
    //     let transition_idx = viterbi.read_outcome_idx();
    //     Bit#(32) data = p_transition.sub(transition_idx);
    //     viterbi.send_outcome_data(data);
    //     // $display("Viterbi Initialization started with n=%0d, m=%0d, outcome=%0d", n, m, outcome);
    // endrule

endmodule
