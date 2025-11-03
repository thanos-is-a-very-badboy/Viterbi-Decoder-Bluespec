package Viterbi_Types;
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
endpackage
