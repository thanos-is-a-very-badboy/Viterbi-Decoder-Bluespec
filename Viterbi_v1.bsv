package Viterbi_v1;
import fp_adder::*;
import Vector::*;

interface Ifc_Viterbi;

    // --- Setup and state loading ---
    method ActionValue#(Bool) get_n_and_m_loaded();
    method Action n_and_m_load(Bit#(5) n, Bit#(5) m);

    // --- Transition / Emission / Outcome data ---
    // method Bit#(10) read_transition_idx();
    // method Bit#(10) read_emission_idx();
    method Bit#(10) read_outcome_idx();

    method Action send_transition_data(Bit#(32) data);
    method Action send_emission_data(Bit#(32) data);
    method Action send_outcome_data(Bit#(32) data);

    // --- Optional: read enables (if your TB checks these flags) ---
    method Bool get_read_transition();
    method Action set_read_transition(Bool val);
    method Bool get_read_emission();
    method Bool get_read_outcome();
    method Bool get_reset_decoder();

    // --- For Final Print ---
    method Print_State get_print_state();
    method Vector#(64, Reg#(Bit#(5))) get_path();
    method Bit#(6) get_num_obs();
    method Bit#(32) get_probab();
    
    // --- For Address Translation ---
    method Bool get_init_done_flag();
    method Bit#(5) get_i_ctr();
    method Bit#(5) get_j_ctr();
    method Bit#(32) get_outcome();

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

typedef enum {
    Init_outcome,
    Read_values,
    Loop,
    Done
} Init_State deriving (Bits, Eq, FShow);

typedef enum {
    Find_max,
    Make_path,
    Go_init,
    All_done
} Print_State deriving (Bits, Eq, FShow);

(* synthesize *)
module mkViterbi(Ifc_Viterbi);

    Ifc_FP32_Adder adder <- mkFP32_Adder(); // internal FP adder

    Reg#(Bit#(5)) n_reg <- mkReg(0);
    Reg#(Bit#(5)) m_reg <- mkReg(0);
    Reg#(Bit#(5)) i_ctr <- mkReg(0);
    Reg#(Bit#(5)) j_ctr <- mkReg(0);
    Reg#(Bit#(10)) t_ctr <- mkReg(0);
    Reg#(Bit#(10)) t_start <- mkReg(0);
    Reg#(Bit#(10)) bt_t_ctr <- mkReg(0);
    Reg#(Bit#(32)) max_reg <- mkReg(32'hFFFFFFFF);
    Reg#(Bit#(5)) max_state_reg <- mkReg(0);

    Reg#(Bit#(32)) bt_max <- mkReg(32'hFFFFFFFF);


    Reg#(Bit#(32)) transition_buffer <- mkReg(0);
    Reg#(Bit#(32)) emission_buffer <- mkReg(0);
    Reg#(Bit#(32)) outcome_buffer <- mkReg(0);

    Reg#(Bit#(10)) outcome_idx <- mkReg(0);

    // prev and curr state vectors
    Vector#(32, Reg#(Bit#(32))) prev <- replicateM(mkReg(32'h0));
    Vector#(32, Reg#(Bit#(32))) curr <- replicateM(mkReg(32'h0));
    Vector#(64, Reg#(Bit#(5))) path <- replicateM(mkReg(0));

    //BackTracking Vector
    Vector#(2048, Reg#(Bit#(5))) bt <- replicateM(mkReg(0));

    // status flags 
    Reg#(Bool) read_transition <- mkReg(False);
    Reg#(Bool) read_emission <- mkReg(False);
    Reg#(Bool) read_outcome <- mkReg(False);
    Reg#(Bool) n_and_m_loaded <- mkReg(False);

    Reg#(Bool) transition_ready <- mkReg(False);
    Reg#(Bool) emission_ready <- mkReg(False);
    Reg#(Bool) outcome_ready <- mkReg(False);

    Reg#(Bool) init_done_flag <- mkReg(False);               
    Reg#(Bool) reset_machine_flag <- mkReg(False);               
    Reg#(Bool) loop_done_flag <- mkReg(False);               
    
    Reg#(State) machine_state <- mkReg(Load_outcome);
    Reg#(Init_State) init_state <- mkReg(Init_outcome);
    Reg#(Print_State) print_state <- mkReg(Find_max);

    // --- rules ---

    rule init_v(!init_done_flag && n_and_m_loaded);
        if(init_state==Init_outcome)begin
            if(!read_outcome && !outcome_ready)begin
                read_outcome<=True;
                outcome_idx<=t_ctr;
            end
            if(outcome_ready)begin
                init_state<=Read_values;
                outcome_ready<=False;
            end
        end
        else if(init_state == Read_values)begin
           if(outcome_buffer==0 && t_ctr!=0) begin
                init_done_flag <= True;
                loop_done_flag <= True;
                print_state <= All_done;
           end
           else if(!transition_ready &&!read_transition && !emission_ready && !read_emission)begin
                read_transition<=True;
                read_emission<=True;
            end
            else if(transition_ready && emission_ready)begin
                init_state <= Loop;
                transition_ready<=False;
                emission_ready<=False;
            end
        end
        else if(init_state == Loop)begin
            let data1 = transition_buffer;
            let data2 = emission_buffer;
            
            if(!adder.state_1_done())begin
                adder.match_exponents(data1, data2);
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
            end
            else if(adder.state_3_done()) begin
         
                let data = adder.get_res();
                adder.clear_adder();
                prev[i_ctr]<=data;

                if(i_ctr<n_reg-1)begin
                    i_ctr<=i_ctr+1;
                    init_state<=Read_values;

                end
                else begin
                    i_ctr<=0;
                    init_done_flag<=True;
                    t_ctr<=t_ctr+1;
                    machine_state<=Load_outcome;
                    loop_done_flag <= False;
                end
            end
        end
    endrule 


    rule loop_rule(init_done_flag && !loop_done_flag);

        if(machine_state == Load_outcome) begin
            if(!read_outcome && !outcome_ready)begin
                read_outcome<=True;
                outcome_idx <= t_ctr;
            end
            else if(outcome_ready) begin
                machine_state <= Load_emission;
                outcome_ready<=False;
            end
        end
        else if(machine_state == Load_emission)begin
            if(outcome_buffer==32'hFFFFFFFF)begin
                reset_machine_flag<=True;
                machine_state<=Print_res;
            end
            else begin
                Bit#(32) temp=0;

                if(!read_emission && !emission_ready)begin
                    read_emission<=True;
                end

                else if(emission_ready)begin
                    machine_state <= Load_trans;
                    emission_ready<=False;
                end
            end
        end

        else if(machine_state==Load_trans) begin
            if(!read_transition && !transition_ready)begin
                read_transition<=True;
            end
            else if(transition_ready)begin
                machine_state <= Sum_and_max;
                transition_ready<=False;
            end
        end
        else if(machine_state==Sum_and_max)begin
            let data1 = prev[j_ctr];
            let data2 = transition_buffer;


            if(!adder.state_1_done())begin
                adder.match_exponents(data1, data2);
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
            end
            else if(adder.state_3_done()) begin
                let data = adder.get_res();
                adder.clear_adder();
                if(i_ctr == 0) begin
                end
                if(data<max_reg && j_ctr<n_reg)begin
                    max_reg <= data;
                    max_state_reg <= j_ctr; 
                end

                if(j_ctr<n_reg-1) begin
                    j_ctr<=j_ctr+1;
                    machine_state<=Load_trans; //might have to remove
                end
                else begin
                    machine_state<=Final_sum;
                end
            end
        end
        else if(machine_state==Final_sum)begin
            j_ctr<=0;

            let data1_dup = max_reg;
            let data2_dup = emission_buffer;

            if(!adder.state_1_done())begin
                adder.match_exponents(data1_dup, data2_dup);
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
            end
            else if(adder.state_3_done()) begin
                let data_dup = adder.get_res();

                curr[i_ctr] <= data_dup;
                
                Bit#(11) bt_index = zeroExtend(t_ctr-t_start)*zeroExtend(n_reg) + zeroExtend(i_ctr);
                bt[bt_index] <= max_state_reg + 1;
                
                max_reg<=32'hFFFFFFFF;
                max_state_reg<=0;
                adder.clear_adder();
                machine_state<=Final_store;

            end
        end
        else if(machine_state==Final_store)begin
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
            end
        end
        else if(machine_state==Print_res)begin
            loop_done_flag<=True;
            i_ctr <= 0;
            print_state <= Find_max;
        end
    endrule

    rule print_rule(loop_done_flag && init_done_flag);
        if(print_state == Find_max) begin
            if(i_ctr < n_reg - 1) begin
                let currval = curr[i_ctr];
                if(currval < bt_max) begin
                    
                    bt_max <= currval;
                    path[t_ctr-t_start] <= i_ctr + 1;
                end
                i_ctr <= i_ctr + 1;
            end
            else begin
                bt_t_ctr <= t_ctr - t_start - 1;
                print_state <= Make_path;

            end
        end

        else if (print_state == Make_path) begin
            if(bt_t_ctr > 0) begin
                let bt_index = (bt_t_ctr)*zeroExtend(n_reg) + zeroExtend(path[bt_t_ctr + 1] -1);
                path[bt_t_ctr] <= bt[bt_index];
                bt_t_ctr <= bt_t_ctr - 1;
            end
            
            else begin                
                Bit#(6) diff = truncate(t_ctr - t_start + 1);
                
                print_state <= Go_init;

            end
        end

        else if (print_state == Go_init) begin
            i_ctr <= 0;
            j_ctr <= 0;
            t_ctr <= t_ctr+1;
            t_start <= t_ctr + 1;
            max_reg <= 32'hFFFFFFFF;
            bt_max <= 32'hFFFFFFFF;
            max_state_reg <= 0;
            init_done_flag <= False;               
            machine_state <= Load_outcome;
            init_state <= Init_outcome;

            for (Integer i = 0; i < 64; i = i + 1) begin
                path[i] <= 0;
            end
        end
        
        
endrule
    // --- methods ---
    
    method ActionValue#(Bool) get_n_and_m_loaded();
        return n_and_m_loaded;
    endmethod 

    method Action n_and_m_load(Bit#(5) n, Bit#(5) m);
        n_reg <= n;
        m_reg <= m;
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

    method Bit#(10) read_outcome_idx();
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

    method Bool get_reset_decoder();
        return reset_machine_flag;
    endmethod

    method Vector#(64, Reg#(Bit#(5))) get_path();
        return path;
    endmethod

    method Print_State get_print_state();
        return print_state;
    endmethod

    method Bit#(6) get_num_obs();
        return truncate(t_ctr - t_start + 1);    
    endmethod

    method Bit#(32) get_probab();
        return bt_max;
    endmethod

    method Bool get_init_done_flag();
        return init_done_flag;
    endmethod

    method Bit#(5) get_i_ctr();
        return i_ctr;
    endmethod

    method Bit#(5) get_j_ctr();
        return j_ctr;
    endmethod

    method Bit#(32) get_outcome();
        return outcome_buffer;
    endmethod

endmodule : mkViterbi
endpackage : Viterbi_v1
