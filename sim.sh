#!/bin/bash

cd /home/shakti/Viterbi-Decoder-Bluespec

make b_sim
diff ./tb_output.dat ./Huge_Ip/output_viterbi_huge.dat