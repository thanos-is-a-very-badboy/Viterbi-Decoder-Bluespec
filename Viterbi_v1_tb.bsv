import Viterbi_v1::*;
import RegFile::*;

(* synthesize *)
module mkViterbiTestbench();

    Ifc_Viterbi viterbi <- mkViterbi();

    // RegFile#(Bit#(32), Bit#(32)) p_transition <- mkRegFileLoad("./Inputs/A_small.dat", 0, 1023);
    // RegFile#(Bit#(32), Bit#(32)) p_emission <- mkRegFileLoad("./Inputs/B_small.dat", 0, 1023);
    // RegFile#(Bit#(32), Bit#(32)) inputs <- mkRegFileLoad("./Inputs/input_small.dat", 0, 1023);
    // RegFile#(Bit#(32), Bit#(32)) n_and_m <- mkRegFileLoad("./Inputs/N_small.dat", 0, 1023);
    
    RegFile#(Bit#(32), Bit#(32)) p_transition <- mkRegFileLoad("./Huge_Ip/A_huge.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) p_emission <- mkRegFileLoad("./Huge_Ip/B_huge.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) inputs <- mkRegFileLoad("./Huge_Ip/input_huge.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(32)) n_and_m <- mkRegFileLoad("./Huge_Ip/N_huge.dat", 0, 1023);

    
    Bit#(32) n = n_and_m.sub(0);
    Bit#(32) m = n_and_m.sub(1);
    // Bit#(32) outcome = inputs.sub(0);

    Reg#(Bool) read_transition_tb <- mkReg(False);
    Reg#(Bool) read_emission_tb <- mkReg(False);
    Reg#(Bool) read_outcome_tb <- mkReg(False);
    
    Reg#(Bit#(32)) transition_idx_tb <- mkReg(32'h0);
    Reg#(Bit#(32)) emission_idx_tb <- mkReg(32'h0);
    Reg#(Bit#(32)) outcome_idx_tb <- mkReg(32'h0);

    rule load_m_and_n;
        let loaded <- viterbi.get_n_and_m_loaded();
        if(!loaded)begin
            viterbi.n_and_m_load(n,m);
        end
    endrule

    rule read_66(viterbi.get_read_transition() && !read_transition_tb);
       read_transition_tb <= True;
       transition_idx_tb <= viterbi.read_transition_idx();
    endrule

    rule read_transition_matrix(read_transition_tb == True);
        Bit#(32) data = p_transition.sub(transition_idx_tb);
        // Bit#(32) data = p_transition.sub(0);
        // $display("In TB: tran_id: %d, prob: %h", transition_idx_tb, data);
        viterbi.send_transition_data(data);
        read_transition_tb <= False;
    endrule

    rule read_77(viterbi.get_read_emission() && !read_emission_tb);
       read_emission_tb <= True;
       emission_idx_tb <= viterbi.read_emission_idx();
    endrule

    rule read_emission_matrix(read_emission_tb == True);
        // if(viterbi.get_read_transition())begin
            
            // $display("I  = %d",transition_idx_tb);
            Bit#(32) data = p_emission.sub(emission_idx_tb);
            // Bit#(32) data = p_transition.sub(0);
            // $display("EMISSION BEING READ with ADDR = %d",emission_idx_tb);
            viterbi.send_emission_data(data);
            read_emission_tb <= False;
            // $display("NYEGA");
        // end
        // $display("Viterbi Initialization started with n=%0d, m=%0d, outcome=%0d", n, m, outcome);
    endrule

    rule read_88(viterbi.get_read_outcome() && !read_outcome_tb);
       read_outcome_tb <= True;
       outcome_idx_tb <= viterbi.read_outcome_idx();
    endrule

    rule read_outcome_matrix(read_outcome_tb == True);
        // $display("Index: %h", outcome_idx_tb);
        Bit#(32) data = inputs.sub(outcome_idx_tb);
        // $display("OUTCOME BEING READ with ADDR = %d",outcome_idx_tb);
        // Bit#(32) data = p_transition.sub(0);
        viterbi.send_outcome_data(data);
        read_outcome_tb <= False;
    endrule

endmodule
