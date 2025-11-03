package fp_adder;

interface Ifc_FP32_Adder;
    method Action match_exponents(Bit#(32) num1, Bit#(32) num2);
    method Action add_mantissa();
    method Action normalise();
    
    method Bit#(32) get_res();
    method Bool state_1_done();
    method Bool state_2_done();
    method Bool state_3_done();  
    method Action clear_adder();
endinterface

(* synthesize *)
module mkFP32_Adder(Ifc_FP32_Adder);

    Reg#(Bool) done1 <- mkReg(False);
    Reg#(Bool) done2 <- mkReg(False);
    Reg#(Bool) done3 <- mkReg(False);

    Reg#(Bit#(32)) res <- mkReg(0);
    Reg#(Bit#(8)) new_exp <- mkReg(0);
    Reg#(Bit#(24)) shifted_mantissa_1 <- mkReg(0);
    Reg#(Bit#(24)) shifted_mantissa_2 <- mkReg(0);
    Reg#(Bit#(23)) final_mantissa <- mkReg(0);

    Reg#(Bit#(1)) guard1 <- mkReg(0);
    Reg#(Bit#(1)) sticky1 <- mkReg(0);
    // Reg#(Bit#(1)) guard2 <- mkReg(0);
    // Reg#(Bit#(1)) sticky2 <- mkReg(0);
    Reg#(Bit#(1)) man_carry <- mkReg(0);
    Reg#(Bit#(8)) diff_reg <- mkReg(0);

    method Action match_exponents(Bit#(32) num1, Bit#(32) num2);
        let exp1 = num1[30:23];
        let exp2 = num2[30:23];
        let man1 = num1[22:0];
        let man2 = num2[22:0];

        Bit#(8) diff=0;
        Bit#(8) newExp=0;
        Bit#(24) sm1=0;
        Bit#(24) sm2=0;
        

        sm1 = {1'b1, man1};
        sm2 = {1'b1, man2};

        let copy_man2 = sm2;

        if (exp1 == exp2) begin
            newExp = exp1;
        end
        else if (exp1 > exp2) begin
            diff = exp1 - exp2;
            // this time shift man2
            sm2 = sm2 >> diff;
            // guard and sticky for round off info later
            if(diff>0)guard1 <= man2[diff-1];
            else guard1 <= 0;

            let shifted_part = copy_man2 & (24'hFFFFFF >> (25 - diff));
            sticky1 <= |shifted_part;
            //  update exponent
            newExp = exp1;
        end
        else begin
            diff = exp2 - exp1;
            // this time shift man1
            sm1 = sm1 >> diff;
            // guard and sticky for round off info later
            if(diff>0) guard1 <= man1[diff-1];
            else guard1 <= 0;

            let shifted_part = copy_man2 & (24'hFFFFFF >> (25 - diff));
            sticky1 <= |shifted_part;
            //  update exponent
            newExp = exp2;  
        end
        // update state once
        shifted_mantissa_1 <= sm1;
        shifted_mantissa_2 <= sm2;
        new_exp <= newExp;
        diff_reg <= diff;
        done1 <= True;
        // $display("exp: %h; mant: %h, %h; diff: %h", newExp, sm1, sm2, diff);
    endmethod

    // stub for now
    method Action add_mantissa();
        // to be implemented later
        let temp_sum_mantissa = {1'b0,shifted_mantissa_1} + {1'b0,shifted_mantissa_2};
        // check carry out
        if(temp_sum_mantissa[24]==1) begin
            // need to shift right by 1
            man_carry <= 1'b1;
            Bit#(1) guard2 = temp_sum_mantissa[0];
            Bit#(1) sticky2 = guard1 | sticky1;
            let temp2_sum_mantissa = temp_sum_mantissa;

            if(guard2==1'b0) begin
                // no rounding
                final_mantissa <= temp2_sum_mantissa[23:1];
                // $display("final_mant: %h", temp2_sum_mantissa[23:1]);

            end
            else if(sticky2==1'b1)begin
                final_mantissa <= temp2_sum_mantissa[23:1] + 1;
                // $display("final_mant: %h", temp2_sum_mantissa[23:1]+1);

            end
            else begin
                if(temp_sum_mantissa[1]==1) begin
                    final_mantissa <= temp2_sum_mantissa[23:1] + 1;
                    // $display("final_mant: %h", temp2_sum_mantissa[23:1]+1);

                end
                else begin
                    final_mantissa <= temp2_sum_mantissa[23:1];
                    // $display("final_mant: %h", temp2_sum_mantissa[23:1]);

                end
            end
        end
        else begin
            // no more shift needed
            man_carry <= 1'b0;
            // only info of prev lowest diff bits needed for rounding
            if(guard1==1'b0)begin
                // no rounding
                final_mantissa <= temp_sum_mantissa[22:0];
                // $display("final_mant: %h", temp_sum_mantissa[22:0]);

            end
            else if(sticky1==1'b1)begin
                final_mantissa <= temp_sum_mantissa[22:0] + 1;
                // $display("final_mant: %h", temp_sum_mantissa[22:0] + 1);

            end
            else begin
                if(temp_sum_mantissa[0]==1) begin
                    final_mantissa <= temp_sum_mantissa[22:0] + 1;
                    // $display("final_mant: %h", temp_sum_mantissa[22:0] + 1);
                end
                else begin
                    final_mantissa <= temp_sum_mantissa[22:0];
                    // $display("final_mant: %h", temp_sum_mantissa[22:0]);

                end
            end
        end
        // $display("exp_addMan: %h", new_exp);
        
        done2<=True;
    endmethod

    // stub for now
    method Action normalise();
        // $display("exp_Norm: %h", new_exp);

        // $display("final_mantossaa: %h", final_mantissa);

        if(man_carry==1'b0) begin
            res <= {1'b1,new_exp,final_mantissa};
            // $display("No_Cout");

            // $display("Final_Result: %h", {1'b1,new_exp,final_mantissa});
            
        end
        else begin
            res <= {1'b1,new_exp+1,final_mantissa};
            // $display("Cout");

            // $display("Final_Result: %h", {1'b1,new_exp + 1,final_mantissa});

        end
        done3<=True;
    endmethod

    method Bit#(32) get_res();
        return res;
    endmethod

    method Bool state_1_done();
        return done1;
    endmethod

    method Bool state_2_done();
        return done2;
    endmethod

    method Bool state_3_done();
        return done3;   
    endmethod

    method Action clear_adder();
        done1<=False;
        done2<=False;
        done3<=False;
    endmethod

endmodule : mkFP32_Adder
endpackage : fp_adder
