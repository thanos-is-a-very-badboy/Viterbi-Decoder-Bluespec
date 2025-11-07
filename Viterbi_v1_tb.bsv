import Viterbi_v1::*;
import RegFile::*;

(* synthesize *)
module mkViterbiTestbench();

    Ifc_Viterbi viterbi <- mkViterbi();

    // RegFile#(Bit#(10), Bit#(32)) p_transition <- mkRegFileLoad("./Inputs/A_small.dat", 0, 1023);
    // RegFile#(Bit#(10), Bit#(32)) p_emission <- mkRegFileLoad("./Inputs/B_small.dat", 0, 1023);
    // RegFile#(Bit#(10), Bit#(32)) inputs <- mkRegFileLoad("./Inputs/input_small.dat", 0, 1023);
    // RegFile#(Bit#(32), Bit#(5)) n_and_m <- mkRegFileLoad("./Inputs/N_small.dat", 0, 1023);
    
    Reg#(File) file <- mkRegU;

    RegFile#(Bit#(10), Bit#(32)) p_transition <- mkRegFileLoad("./Huge_Ip/A_huge.dat", 0, 1023);
    RegFile#(Bit#(10), Bit#(32)) p_emission <- mkRegFileLoad("./Huge_Ip/B_huge.dat", 0, 1023);
    RegFile#(Bit#(10), Bit#(32)) inputs <- mkRegFileLoad("./Huge_Ip/input_huge.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(5)) n_and_m <- mkRegFileLoad("./Huge_Ip/N_huge.dat", 0, 1023);
    

    Bit#(5) n = n_and_m.sub(0);
    Bit#(5) m = n_and_m.sub(1);
    // Bit#(32) outcome = inputs.sub(0);

    Reg#(Bool) read_transition_tb <- mkReg(False);
    Reg#(Bool) read_emission_tb <- mkReg(False);
    Reg#(Bool) read_outcome_tb <- mkReg(False);
    Reg#(Bool) print_done <- mkReg(True);
    Reg#(Bool) file_opened <- mkReg(False);


    Reg#(Bit#(10)) transition_idx_tb <- mkReg(0);
    Reg#(Bit#(10)) emission_idx_tb <- mkReg(0);
    Reg#(Bit#(10)) outcome_idx_tb <- mkReg(0);

    rule open_file(!file_opened);
        let f <- $fopen("tb_output.dat", "w");
        file <= f;
        file_opened <= True;
    endrule

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

    rule print_final_result;
        let print_state = viterbi.get_print_state();
        
        if(print_state == Make_path && print_done == True) begin
            // $display("Getting Ready to Print");
            print_done <= False;
        end

        else if(print_state == Go_init && print_done == False) begin
            let path = viterbi.get_path();
            let diff = viterbi.get_num_obs();
            let probab = viterbi.get_probab();

            for (Integer i = 1; fromInteger(i) < diff; i = i + 1) begin
                Bit#(32) ext  = zeroExtend(path[fromInteger(i)]);
                $display("Path: %h", ext);
                $fwrite(file, "%h\n", ext);
            end
            $display("- - - - - - - - - - - - - - - - - - - - - - - - - -");

            $display("Probab:  %h", probab);
            $fwrite(file, "%h\n", probab);
            $fwrite(file, "ffffffff\n");
            $display("- - - - - - - - - - - - - - - - - - - - - - - - - -");

            print_done <= True;
        end

        else if (print_state == All_done) begin
            $display("All Inputs Done");
            $fwrite(file, "00000000\n");
            $fclose(file);
            $finish(0);
        end
        
    endrule
endmodule
