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

    // --- Load values into Registers ---
    method Action load_from_outcome(Bit#(32) idx);
    method Action load_from_emission(Bit#(32) idx);
    method Action load_from_transition(Bit#(32) idx);

endinterface

typedef enum {
    Load_outcome,
    Load_emission,
    Load_trans,
    Sum_and_max,
    Reset_j_loop,
    Final_sum,
    Final_store,
    Print_res,
    Finish
} State deriving (Bits, Eq, FShow);

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
    Reg#(Bit#(32)) max_reg <- mkReg(32'hFFFFFFFF);
    Reg#(Bit#(32)) max_state_reg <- mkReg(32'hFFFFFFFF);


    Reg#(Bit#(32)) transition_buffer <- mkReg(0);
    Reg#(Bit#(32)) emission_buffer <- mkReg(0);
    Reg#(Bit#(32)) outcome_buffer <- mkReg(0);

    Reg#(Bit#(32)) transition_idx <- mkReg(0);
    Reg#(Bit#(32)) emission_idx <- mkReg(0);
    Reg#(Bit#(32)) outcome_idx <- mkReg(0);

    // prev and curr state vectors
    Vector#(32, Reg#(Bit#(32))) prev <- replicateM(mkReg(32'h0));
    Vector#(32, Reg#(Bit#(32))) curr <- replicateM(mkReg(32'h0));

    Vector#(64, Vector#(32, Reg#(Bit#(32)))) bt <- replicateM(replicateM(mkReg(0)));

    // status flags 
    Reg#(Bool) read_transition <- mkReg(False);
    Reg#(Bool) read_emission <- mkReg(False);
    Reg#(Bool) read_outcome <- mkReg(False);
    Reg#(Bool) n_and_m_loaded <- mkReg(False);

    Reg#(Bool) transition_ready <- mkReg(False);
    Reg#(Bool) emission_ready <- mkReg(False);
    Reg#(Bool) outcome_ready <- mkReg(False);

    Reg#(Bool) init_in_progress <- mkReg(False);
    Reg#(Bool) init_done_flag <- mkReg(False);               
    Reg#(Bool) loop_done_flag <- mkReg(False);               
   
   Reg#(State) machine_state <- mkReg(Load_outcome);
    // --- rules ---

    rule init_v(!init_done_flag && n_and_m_loaded);
        //  want to read memory so issue request
        if(!transition_ready &&!read_transition && !emission_ready && !read_emission)begin
            read_transition<=True;
            read_emission<=True;

            transition_idx<=i_ctr;
            emission_idx<=i_ctr*m_reg + outcome_reg;
        end
        else if(transition_ready && emission_ready)begin
            // can do addition
            let data1 = transition_buffer;
            let data2 = emission_buffer;
            // //$display("NYEGA");
            
            if(!adder.state_1_done())begin
                adder.match_exponents(data1, data2);
                // //$display("Matching exponents...");
                // started <= True;
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
                // //$display("Mantissas added");
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
                // //$display("Normalization done");
            end
            else if(adder.state_3_done()) begin
        // Step 2: wait for state_1_done
                
                let data = adder.get_res();
                adder.clear_adder();
                prev[i_ctr]<=data;
                // $display("A: %h, B : %h, S: %h", data1, data2, data);

                // //$display("NYEGA, %d", i_ctr);
                read_transition<=False;
                read_emission<=False;
                transition_ready<=False;
                emission_ready<=False;

                if(i_ctr<n_reg-1)begin
                    i_ctr<=i_ctr+1;
                    // //$display("VALUE of I : %d",i_ctr);
                end
                else begin
                    i_ctr<=0;
                    init_done_flag<=True;
                    t_ctr<=t_ctr+1;
                end
            end
        end
    endrule 

    // rule done_init (init_done_flag && machine_state == Load_outcome);
    //     $display("Viterbi Initialization completed.");
    //     // $display("N and M = %d, %d", n_reg, m_reg);

    //     // $finish(0);
        
    //     for (Integer i = 0; fromInteger(i) < 2; i = i + 1) begin
    //         $display("I: %d, P : %h", i, prev[i]);
    //     end

    //     $display("----------------------------------------------------------");
    // endrule

    rule loop_rule(init_done_flag);
        // //$display("Loop Begins");

        if(machine_state == Load_outcome) begin
            if(!read_outcome && !outcome_ready)begin
                read_outcome<=True;
                outcome_idx <= t_ctr;
            end
            // load_from_outcome(t_ctr);
            else if(outcome_ready) begin
                machine_state <= Load_emission;
                outcome_ready<=False;
            end
        end
        else if(machine_state == Load_emission)begin
            // $display("Outcome: %h", outcome_buffer);
            // $display("T: %d| i: %d, Emission : %h",t_ctr, i_ctr, emission_buffer, emission_idx);
            // $display("T: %d| i: %d, Outcome : %h",t_ctr, i_ctr, outcome_buffer, outcome_idx);
            if(outcome_buffer==32'hFFFFFFFF)begin
                $display("...................EOS REACHED...................");
                machine_state<=Print_res;
            end
            //$display("Loading emission in loop");
            else begin
                
                Bit#(32) temp=0;

                if(!read_emission && !emission_ready)begin
                    read_emission<=True;
                    temp = outcome_buffer - 1;
                    // $display("I CTR : %d, temp : %d",i_ctr,temp);
                    emission_idx <= i_ctr*m_reg + temp;
                end

                else if(emission_ready)begin
                    // $display("------------------------------------------------");
                    // $display("T: %d| i: %d, Emission : %h, Outcome_buffer : %d , Outcome_idx : %d",t_ctr, i_ctr, emission_buffer, outcome_buffer,outcome_idx);
                    machine_state <= Load_trans;
                    emission_ready<=False;
                end
            end
        end

        else if(machine_state==Load_trans) begin
            //$display("Loading transition in loop");
            if(!read_transition && !transition_ready)begin
                read_transition<=True;
                transition_idx <= (j_ctr+1)*n_reg + i_ctr;
            end
            // $display("WTF: %d, %d", i_ctr, j_ctr);
            else if(transition_ready)begin
                // $display("tran_in_load_trans_state: %h, idx: %d, (i, j): (%d,%d)", transition_buffer, (j_ctr+1)*n_reg + i_ctr, i_ctr, j_ctr);
                machine_state <= Sum_and_max;
                transition_ready<=False;
            end
        end
        else if(machine_state==Sum_and_max)begin
            let data1 = prev[j_ctr];
            let data2 = transition_buffer;

            // $display("READ TRANSITION : %d TRANSITION READY : %d ",pack(read_transition),pack(transition_ready));
            // $display("READ EMISSION : %d EMISSION READY : %d ",pack(read_emission),pack(emission_ready));
            // $display("READ OUTCOME : %d OUTCOME READY : %d ",pack(read_outcome),pack(outcome_ready));

            if(!adder.state_1_done())begin
                adder.match_exponents(data1, data2);
                // //$display("Matching exponents...");
                // started <= True;
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
                // //$display("Mantissas added");
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
                // //$display("Normalization done");
            end
            else if(adder.state_3_done()) begin
        // Step 2: wait for state_1_done
                let data = adder.get_res();
                adder.clear_adder();
                // $display("T: %d | i: %d,j : %d, curr : %h, prev: %h, tran : %h ", t_ctr, i_ctr, j_ctr,  data, prev[j_ctr], transition_buffer);
                if(i_ctr == 0) begin
                // $display("%h, %h, %h |  %d, %d, %d",prev[j_ctr], transition_buffer, data, t_ctr, i_ctr, j_ctr);
                end
                if(data<max_reg && j_ctr<n_reg)begin
                    // if(i_ctr == 0) begin
                    //     $display("YooHoo");
                    // end
                    max_reg <= data;
                    max_state_reg <= j_ctr; 
                end

                if(j_ctr<n_reg-1) begin
                    j_ctr<=j_ctr+1;
                    machine_state<=Load_trans; //might have to remove
                    // //$display("J counter val : %h",j_ctr);
                end
                else begin
                    machine_state<=Final_sum;
                    // if(i_ctr == 0) begin
                    // end
                end
                    // //$display(machine_state);
                    //$display("Sum and Max Stage Done");
                // $display("MAX REG: %h | DATA: %h", max_reg, data);
            end
        end
        else if(machine_state==Final_sum)begin
            j_ctr<=0;

            let data1_dup = max_reg;
            let data2_dup = emission_buffer;

            // $display("MAX REG : %h",max_reg);
            
            if(!adder.state_1_done())begin
                adder.match_exponents(data1_dup, data2_dup);
                //$display("Matching exponents...");
                // started <= True;
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
                //$display("Mantissas added");
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
                //$display("Normalization done");
            end
            else if(adder.state_3_done()) begin
        // // Step 2: wait for state_1_done
                //$display("MAA KI CHEW");
                let data_dup = adder.get_res();

                // $display("data no : %h | I: %d",data_dup, i_ctr);
                // $display("State: %d, Prob: %h, max_reg:%h, em_buff:%h",i_ctr, data_dup, max_reg, emission_buffer);

                curr[i_ctr] <= data_dup;
                // bt[t_ctr][i_ctr] <= max_state_reg;
                max_reg<=32'hFFFFFFFF;
                max_state_reg<=0;
                adder.clear_adder();
                machine_state<=Final_store;

                // $display("I: %d, curr : %h, inA: %h, inB : %h ", i_ctr, data_dup, data1_dup, data2_dup);

            end
            //$display("NYEGA");
        end
        else if(machine_state==Final_store)begin
            // $finish(0);
            // $display("I: %d, curr : %h, prev: %h ", i_ctr, curr[i_ctr], prev[i_ctr]);
            
            if(i_ctr < n_reg - 1) begin
                machine_state<=Load_emission;
                i_ctr<=i_ctr+1;
            end
            else begin
                
                for (Integer i = 0; fromInteger(i) < 32; i = i + 1) begin
                    prev[i] <= curr[i];
                end
                
                machine_state<=Load_outcome;
                i_ctr <=0;
                t_ctr<=t_ctr+1;
                // $display("YOOHOOO T %d", t_ctr);
                // $finish(0);
            end
        end
        else if(machine_state==Print_res)begin
            // loop_done_flag<=True;
            for (Integer i = 0; fromInteger(i) < 2; i = i + 1) begin
                $display("I: %d, P : %h", i, curr[i]);
            end
            $finish(0);
        end
    endrule
    // --- methods ---

    method Action load_from_outcome(Bit#(32) idx);
        read_outcome<=True;
        outcome_idx <= idx;
    endmethod
    
    method Action load_from_transition(Bit#(32) idx);
        read_transition<=True;
        transition_idx <= idx;
    endmethod
    
    method ActionValue#(Bool) get_n_and_m_loaded();
        // read_transition<=True;
        // read_emission<=True;
        return n_and_m_loaded;
    endmethod 

    method Action n_and_m_load(Bit#(32) n, Bit#(32) m,Bit#(32)outcome1);
        n_reg <= n;
        m_reg <= m;
        outcome_reg<=outcome1-1;
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
        outcome_ready <= True;
        read_outcome <= False;
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
