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
    Final_sum,
    Final_store
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
            // $display("NYEGA");
            
            if(!adder.state_1_done())begin
                adder.match_exponents(data1, data2);
                // $display("Matching exponents...");
                // started <= True;
            end
            else if(adder.state_1_done() && !adder.state_2_done())begin
                adder.add_mantissa();     
                // $display("Mantissas added");
            end
            else if(adder.state_2_done() && !adder.state_3_done())begin
                adder.normalise();
                // $display("Normalization done");
            end
            else if(adder.state_3_done()) begin
        // Step 2: wait for state_1_done
                let data = adder.get_res();
                adder.clear_adder();
                prev[i_ctr]<=data;
                $display("A: %h, B : %h, S: %h", data1, data2, data);

                // $display("NYEGA, %d", i_ctr);
                read_transition<=False;
                read_emission<=False;
                transition_ready<=False;
                emission_ready<=False;

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
        end
    endrule 

    rule done_init (init_done_flag);
        $display("Viterbi Initialization completed.");
        $display("N and M = %d, %d", n_reg, m_reg);

        // for (Integer i = 0; fromInteger(i) < 8; i = i + 1) begin
        //     // $display("I: %d, P : %h", i, prev[i]);
        // end

        
    endrule

    rule loop_rule(init_done_flag && !loop_done_flag);
        // $display("Boooyeahhh");

        if(machine_state == Load_outcome) begin
            read_outcome<=True;
            outcome_idx <= t_ctr;
            // load_from_outcome(t_ctr);
            if(outcome_ready) begin
                machine_state <= Load_emission;
            end
        end
        else if(machine_state == Load_emission)begin
            $display("Loading emission in loop");
            read_emission<=True;
            let temp = outcome_buffer - 1;
            emission_idx <= i_ctr*m_reg + temp;
            if(emission_ready)begin
                machine_state <= Load_trans;
            end
        end
        else begin
            $display("EMISSION VALUE = %h",emission_buffer);
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
    
    method Action load_from_emission(Bit#(32) idx);

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
