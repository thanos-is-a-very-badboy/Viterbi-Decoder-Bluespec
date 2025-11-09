package Viterbi_v1;
import fp_adder::*;
import Vector::*;

interface Ifc_Viterbi;

    // --- Setup and state loading ---
    method ActionValue#(Bool) get_n_and_m_loaded();
    method Action n_and_m_load(Bit#(5) n, Bit#(5) m);

    // --- Transition / Emission / Outcome data ---
    method Bit#(10) read_outcome_idx();

    method Action send_transition_data(Bit#(32) data);
    method Action send_emission_data(Bit#(32) data);
    method Action send_outcome_data(Bit#(32) data);

    // --- Optional: read enables (if your TB checks these flags) ---
    method Bool get_read_transition();
    method Bool get_read_emission();
    method Bool get_read_outcome();

    // --- For Final Print ---
    method Print_State get_print_state();
    method Bit#(6) get_num_obs();
    method Bit#(32) get_probab();
    
    // --- For Address Translation ---
    method Bool get_init_done_flag();
    method Bit#(5) get_i_ctr();
    method Bit#(5) get_j_ctr();
    method Bit#(32) get_outcome();

    // --- To Write into BT Memory ---
    method Bool get_write_to_bt_flag();
    method Bit#(5) get_max_stage_reg(); 

    // --- To Read data from BT Memory ---
    method Bool get_read_bt();
    method Bit#(10) get_bt_t_ctr();
    method Action send_bt_data(Bit#(5) data);

    // --- To Send Path Array Elements ---
    method Bit#(5) get_path_buffer();
    method Bool get_path_ready();
        
    // --- Write into Curr Array ---
    method Bit#(32) get_curr_buffer();
    method Bool get_write_to_curr_flag();

    // --- To Read Values from Curr ---
    method Bool get_read_curr();
    method Action send_curr_data(Bit#(32) data);

    // --- To Read Values from Prev ---
    method Bool get_read_prev();
    method Action send_prev_data(Bit#(32) data);
    
    // --- To Write into Prev Buffer ---
    method Bool get_write_to_prev_flag();
    method Bit#(32) get_prev_buffer();
    
    // --- Swap Prev and Curr at the End of 2 Inner Loops ---
    method Bool get_switch_prev_curr();
    
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

    //N and M
    Reg#(Bit#(5)) n_reg <- mkReg(0);
    Reg#(Bit#(5)) m_reg <- mkReg(0);
    
    //Loop Counters
    Reg#(Bit#(5)) i_ctr <- mkReg(0);
    Reg#(Bit#(5)) j_ctr <- mkReg(0);
    Reg#(Bit#(10)) t_ctr <- mkReg(0);

    //t at Beginning of Each Sequence
    Reg#(Bit#(10)) t_start <- mkReg(0);

    //Used in Backtracking
    Reg#(Bit#(10)) bt_t_ctr <- mkReg(0);

    //Maximum Probability and Corresponding Register
    Reg#(Bit#(32)) max_reg <- mkReg(32'hFFFFFFFF);
    Reg#(Bit#(5)) max_state_reg <- mkReg(0);

    //Max Probability Register in BT Stage
    Reg#(Bit#(32)) bt_max <- mkReg(32'hFFFFFFFF);

    //Buffer to Read from Transition, Emission, Outcome, BT
    Reg#(Bit#(32)) transition_buffer <- mkReg(0);
    Reg#(Bit#(32)) emission_buffer <- mkReg(0);
    Reg#(Bit#(32)) outcome_buffer <- mkReg(0);
    Reg#(Bit#(5)) bt_buffer <- mkReg(0);

    //Index to Read from Outcome (t)
    Reg#(Bit#(10)) outcome_idx <- mkReg(0);

    //Path Array Element for Top Module
    Reg#(Bit#(5)) path_buffer <- mkReg(0);
    
    //Indicates path_buffer is to be Read
    Reg#(Bool) path_ready <- mkReg(False);

    //To Store Path[t+1]   
    Reg#(Bit#(5)) max_path <- mkReg(0);

    //Set to Indicate Data is to be Read
    Reg#(Bool) read_transition <- mkReg(False);
    Reg#(Bool) read_emission <- mkReg(False);
    Reg#(Bool) read_outcome <- mkReg(False);
    Reg#(Bool) read_bt <- mkReg(False);
    Reg#(Bool) read_curr <- mkReg(False);
    Reg#(Bool) read_prev <- mkReg(False);

    //Set when n and m are loaded
    Reg#(Bool) n_and_m_loaded <- mkReg(False);

    //Set when Data is Ready
    Reg#(Bool) transition_ready <- mkReg(False);
    Reg#(Bool) emission_ready <- mkReg(False);
    Reg#(Bool) outcome_ready <- mkReg(False);
    Reg#(Bool) bt_ready <- mkReg(False);
    Reg#(Bool) curr_ready <- mkReg(False);
    Reg#(Bool) prev_ready <- mkReg(False);

    //Indicates Finishing of Initialization, Loop Completion
    Reg#(Bool) init_done_flag <- mkReg(False);                       
    Reg#(Bool) loop_done_flag <- mkReg(False);               
    
    //Indicate Write to Memory
    Reg#(Bool) write_to_bt_flag <- mkReg(False);  
    Reg#(Bool) write_to_curr_flag <- mkReg(False);
    Reg#(Bool) write_to_prev_flag <- mkReg(False);             

    //FSM States for Each Part of Computation
    Reg#(State) machine_state <- mkReg(Load_outcome);
    Reg#(Init_State) init_state <- mkReg(Init_outcome);
    Reg#(Print_State) backtrack_state <- mkReg(Find_max);
    
    //Element of curr and prev; Used for Viterbi-Top and Top-Viterbi Transfer
    Reg#(Bit#(32)) curr_buffer <- mkReg(0);
    Reg#(Bit#(32)) prev_buffer <- mkReg(0);
    
    //prev <- curr Load to be Done
    Reg#(Bool) switch_prev_curr <- mkReg(False);

    // --- rules ---

    //Initialize (Load Values for t=0)
    rule init_v(!init_done_flag && n_and_m_loaded);

        //Load the First Value from input.dat
        if(init_state==Init_outcome)begin
            //Read From input.dat values
            if(!read_outcome && !outcome_ready)begin
                read_outcome<=True;
                outcome_idx<=t_ctr;
            end
            else if(outcome_ready)begin
                init_state<=Read_values;
                outcome_ready<=False;
            end
        end
        
        //Read Transition, Emission for 1st Transition
        else if(init_state == Read_values)begin
            write_to_prev_flag <= False;

            //Final Exit Condition (Read 0)
           if(outcome_buffer==0 && t_ctr!=0) begin
                init_done_flag <= True;
                loop_done_flag <= True;
                backtrack_state <= All_done;
           end

           //Read from A Matrix
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

        //Calculate A[0][i] + B[i][Outcome]; Increment i
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
                
                prev_buffer <= data;
                write_to_prev_flag <= True;

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

    // All 3 Loops- t, i ,j Loops
    rule loop_rule(init_done_flag && !loop_done_flag);
        
        //Load input.dat Values
        if(machine_state == Load_outcome) begin
            write_to_prev_flag <= False;
            switch_prev_curr <= False;
            
            if(!read_outcome && !outcome_ready)begin
                read_outcome<=True;
                outcome_idx <= t_ctr;
            end
            else if(outcome_ready) begin
                machine_state <= Load_emission;
                outcome_ready<=False;
            end
        end

        //Load B[i][Output]
        else if(machine_state == Load_emission)begin
            
            //Finish of One i Loop - Reset Registers; Go to Initialize
            if(outcome_buffer==32'hFFFFFFFF)begin
                machine_state<=Print_res;
            end

            //Load B[i][Output]
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

        // Read B[j][i] 
        else if(machine_state==Load_trans) begin

            if(!read_transition && !transition_ready)begin
                read_transition<=True;
            end
            else if(transition_ready)begin
                machine_state <= Sum_and_max;
                transition_ready<=False;
            end
        end

        // Calculate prev[j] + B[j][i]; Find Max
        else if(machine_state==Sum_and_max)begin
            
            if(!read_prev && !prev_ready)begin
                read_prev <= True;
            end
                
            else if(prev_ready)begin
                prev_ready <= False;
                let data1 = prev_buffer;
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
                    // if(i_ctr == 0) begin
                    // end

                    //Update Max Probability, Max State
                    if(data<max_reg && j_ctr<n_reg)begin
                        max_reg <= data;
                        max_state_reg <= j_ctr; 
                    end

                    //Update j Counter; Go Back to Loading A[j][i]
                    if(j_ctr<n_reg-1) begin
                        j_ctr<=j_ctr+1;
                        machine_state<=Load_trans; //might have to remove
                    end
                    
                    //Go to Calculate Max(prev[j] + A[j][i]) + B[i][Outcome]
                    else begin
                        machine_state<=Final_sum;
                    end

                end
            end
        end

        //Calculate Max(prev[j] + A[j][i]) + B[i][Outcome]
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

                //Write Sum to Curr Array
                curr_buffer <= data_dup;
                write_to_curr_flag <= True;
                
                //Update BT Array
                write_to_bt_flag <= True;

                max_reg<=32'hFFFFFFFF;
                adder.clear_adder();
                machine_state<=Final_store;

            end
        end

        // Update i Counter and/or t Counter
        else if(machine_state==Final_store)begin
            
            max_state_reg<=0;
            write_to_curr_flag <= False;
            write_to_bt_flag <= False;

            if(i_ctr < n_reg - 1) begin
                machine_state<=Load_emission;
                i_ctr<=i_ctr+1;
            end
            
            //prev <= curr if i Loop Done
            else begin
                switch_prev_curr <= True;    
                machine_state<=Load_outcome;
                i_ctr <=0;
                t_ctr<=t_ctr+1;
            end
        end

        //Loops Done; Go to Backtracking
        else if(machine_state==Print_res)begin
            loop_done_flag<=True;
            i_ctr <= 0;
            backtrack_state <= Find_max;
        end
    endrule

    //Backtracking & Finding Path
    rule backtrack_rule(loop_done_flag && init_done_flag);

        //Find Most Probable Last State
        if(backtrack_state == Find_max) begin
            if(i_ctr < n_reg - 1) begin
                
                if(!read_curr && !curr_ready)begin
                    read_curr <= True;
                end
                
                else if(curr_ready)begin
                    curr_ready <= False;
                    let currval = curr_buffer;

                    if(currval < bt_max) begin
                        
                        bt_max <= currval;

                        max_path <= i_ctr + 1;
                        path_buffer <= i_ctr + 1;
                    end
                    i_ctr <= i_ctr + 1;
                end
            end

            //i Loop Done; Begin Making Rest of the Path
            else begin
                bt_t_ctr <= t_ctr - t_start - 1;
                backtrack_state <= Make_path;
                path_ready <= True;
            end
        end

        //Make the Rest of the Path
        else if (backtrack_state == Make_path) begin
            
            //Read from BT Array; Find Next Element of Path
            if(bt_t_ctr > 0) begin
                if(!read_bt && !bt_ready)begin
                    read_bt <= True;
                    path_buffer <= max_path;
                    path_ready <= False;
                end
                
                if(bt_ready)begin
                    max_path <= bt_buffer;
                    bt_ready <= False;
                    path_ready <= True;
                    path_buffer <= bt_buffer;
                    bt_t_ctr <= bt_t_ctr - 1;
                end
            end
            
            //State before Initializing; Clearing Registers
            else begin                
                backtrack_state <= Go_init;
            end
        end

        //Reset & Clear Registers
        else if (backtrack_state == Go_init) begin
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
            path_ready <= False;
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

    // method Action set_read_transition(Bool val);
    //     read_transition <= val;
    // endmethod

    method Bool get_read_emission();
        return read_emission;
    endmethod

    method Bool get_read_outcome();
        return read_outcome;
    endmethod

    // method Bool get_reset_decoder();
        // return reset_machine_flag;
    // endmethod

    method Print_State get_print_state();
        return backtrack_state;
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

    // method State get_machine_state();
    //     return machine_state;
    // endmethod

    method Bit#(5) get_max_stage_reg();
        return max_state_reg;
    endmethod

    method Bool get_write_to_bt_flag();
        return write_to_bt_flag;
    endmethod

    method Bool get_read_bt();
        return read_bt;
    endmethod

    method Bit#(10) get_bt_t_ctr();
        return bt_t_ctr;
    endmethod

    method Bit#(5) get_path_buffer();
        return path_buffer;
    endmethod

    method Action send_bt_data(Bit#(5) data);
        bt_buffer <= data;
        bt_ready <= True;
        read_bt <= False;
    endmethod

    method Bool get_path_ready();
        return path_ready;    
    endmethod

    method Bool get_write_to_curr_flag();
        return write_to_curr_flag;
    endmethod

    method Bit#(32) get_curr_buffer();
        return curr_buffer;
    endmethod

    method Bool get_read_curr();
        return read_curr;
    endmethod
    
    method Action send_curr_data(Bit#(32) data);
        curr_buffer <= data;
        curr_ready <= True;
        read_curr <= False;
    endmethod

    method Bool get_write_to_prev_flag();
        return write_to_prev_flag;
    endmethod

    method Bool get_read_prev();
        return read_prev;
    endmethod
    
    method Action send_prev_data(Bit#(32) data);
        prev_buffer <= data;
        prev_ready <= True;
        read_prev <= False;
    endmethod
    
    method Bool get_switch_prev_curr();
        return switch_prev_curr;
    endmethod

    method Bit#(32) get_prev_buffer();
        return prev_buffer;
    endmethod

endmodule : mkViterbi
endpackage : Viterbi_v1
