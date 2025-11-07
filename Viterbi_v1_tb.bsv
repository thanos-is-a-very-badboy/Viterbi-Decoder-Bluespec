import Viterbi_v1::*;
import RegFile::*;
import Vector :: *;

(* synthesize *)
module mkViterbiTestbench();

    Ifc_Viterbi viterbi <- mkViterbi();

    // RegFile#(Bit#(10), Bit#(32)) p_transition <- mkRegFileLoad("./Inputs/A_small.dat", 0, 1023);
    // RegFile#(Bit#(10), Bit#(32)) p_emission <- mkRegFileLoad("./Inputs/B_small.dat", 0, 1023);
    // RegFile#(Bit#(10), Bit#(32)) inputs <- mkRegFileLoad("./Inputs/input_small.dat", 0, 1023);
    // RegFile#(Bit#(32), Bit#(5)) n_and_m <- mkRegFileLoad("./Inputs/N_small.dat", 0, 1023);
    
    Vector#(2048, Reg#(Bit#(5))) bt_tb <- replicateM(mkReg(0));
    
    Reg#(File) file <- mkRegU;

    RegFile#(Bit#(10), Bit#(32)) p_transition <- mkRegFileLoad("./Huge_Ip/A_huge.dat", 0, 1023);
    RegFile#(Bit#(10), Bit#(32)) p_emission <- mkRegFileLoad("./Huge_Ip/B_huge.dat", 0, 1023);
    RegFile#(Bit#(10), Bit#(32)) inputs <- mkRegFileLoad("./Huge_Ip/input_huge.dat", 0, 1023);
    RegFile#(Bit#(32), Bit#(5)) n_and_m <- mkRegFileLoad("./Huge_Ip/N_huge.dat", 0, 1023);
    

    Bit#(5) n = n_and_m.sub(0);
    Bit#(5) m = n_and_m.sub(1);

    Reg#(Bool) read_transition_tb <- mkReg(False);
    Reg#(Bool) read_emission_tb <- mkReg(False);
    Reg#(Bool) read_outcome_tb <- mkReg(False);
    Reg#(Bool) read_bt_tb <- mkReg(False);

    Reg#(Bool) print_done <- mkReg(True);
    Reg#(Bool) file_opened <- mkReg(False);


    Reg#(Bit#(10)) transition_idx_tb <- mkReg(0);
    Reg#(Bit#(10)) emission_idx_tb <- mkReg(0);
    Reg#(Bit#(10)) outcome_idx_tb <- mkReg(0);
    Reg#(Bit#(10)) bt_idx_tb <- mkReg(0);

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

        if(!viterbi.get_init_done_flag()) begin
            let i_ctr = viterbi.get_i_ctr();
            transition_idx_tb <= zeroExtend(i_ctr);
        end
        else begin
            let i_ctr = viterbi.get_i_ctr();
            let j_ctr = viterbi.get_j_ctr();
            transition_idx_tb <= zeroExtend(j_ctr+1)*zeroExtend(n) + zeroExtend(i_ctr);
        end
    endrule

    rule read_transition_matrix(read_transition_tb == True);
        Bit#(32) data = p_transition.sub(transition_idx_tb);
        viterbi.send_transition_data(data);
        read_transition_tb <= False;
    endrule

    rule read_77(viterbi.get_read_emission() && !read_emission_tb);
        read_emission_tb <= True;
        let i_ctr = viterbi.get_i_ctr();
        let outcome = viterbi.get_outcome();
        emission_idx_tb <= zeroExtend(i_ctr)*zeroExtend(m) + truncate(outcome-1);
    endrule

    rule read_emission_matrix(read_emission_tb == True);
        Bit#(32) data = p_emission.sub(emission_idx_tb);
        viterbi.send_emission_data(data);
        read_emission_tb <= False;
    endrule

    rule read_88(viterbi.get_read_outcome() && !read_outcome_tb);
       read_outcome_tb <= True;
       outcome_idx_tb <= viterbi.read_outcome_idx();
    endrule

    rule read_outcome_matrix(read_outcome_tb == True);
        Bit#(32) data = inputs.sub(outcome_idx_tb);
        viterbi.send_outcome_data(data);
        read_outcome_tb <= False;
    endrule

    rule print_final_result;
        let print_state = viterbi.get_print_state();
        
        if(print_state == Make_path && print_done == True) begin
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
            // $display("In Tb");
            // for (Integer i = 0; fromInteger(i) < 32; i = i + 1) begin
            //     $display("BT[%d]: %d",i, bt_tb[i] );
            // end
            $finish(0);
        end

    endrule

    rule write_to_bt(viterbi.get_write_to_bt_flag() == True);
        let i_ctr = viterbi.get_i_ctr();
        
        if(i_ctr < n) begin
            let bt_t_ctr = viterbi.get_num_obs()-1;
            let max_state_reg = viterbi.get_max_stage_reg() + 1;
            Bit#(11) bt_index = zeroExtend(bt_t_ctr)*zeroExtend(n) + zeroExtend(i_ctr);
            bt_tb[bt_index] <= max_state_reg;
        end
    endrule

    rule read_99(viterbi.get_read_bt() && !read_bt_tb);
       read_bt_tb <= True;
       let bt_t_ctr = viterbi.get_bt_t_ctr();
       let path_buffer = viterbi.get_path_buffer() - 1;
       bt_idx_tb <= (bt_t_ctr)*zeroExtend(n) + zeroExtend(path_buffer);
    endrule

    rule read_bt(read_bt_tb == True);
        Bit#(5) data = bt_tb[bt_idx_tb];
        viterbi.send_bt_data(data);
        read_bt_tb <= False;
    endrule

endmodule
