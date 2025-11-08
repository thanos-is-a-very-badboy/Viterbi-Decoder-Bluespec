import numpy as np
import struct

def read_float32_data(filepath, mode='exp'):
    """
    Reads a file of hex strings and converts them to uint32 bit patterns.
    """
    import numpy as np
    with open(filepath, 'r') as f:
        hex_strings = [line.strip() for line in f.readlines() if line.strip()]

    if mode == 'raw':
        return hex_strings

    integer_values = [int(h, 16) for h in hex_strings]
    integer_array = np.array(integer_values, dtype=np.uint32)
    return integer_array


def read_dimensions(filepath):
    with open(filepath, 'r') as f:
        N = int(f.readline().strip(), 16)
        M = int(f.readline().strip(), 16)
    return N, M

def summer_hw_emulation(x_uint, y_uint):
    """
    Emulates the pipelined adder.
    """
    
    # Unpack values
    exp_x = (x_uint >> 23) & 0xFF
    man_x = x_uint & 0x7FFFFF
    
    exp_y = (y_uint >> 23) & 0xFF
    man_y = y_uint & 0x7FFFFF
    
    # Handle zero
    if exp_x == 0 and man_x == 0:
        return y_uint
    if exp_y == 0 and man_y == 0:
        return x_uint
        
    # Add implicit bit
    man_x_24 = man_x | 0x800000
    man_y_24 = man_y | 0x800000
    
    # Align mantissas
    new_exp = 0
    sm1 = man_x_24
    sm2 = man_y_24
    guard1 = 0
    sticky1 = 0
    diff = 0
    
    if exp_x == exp_y:
        new_exp = exp_x
    
    elif exp_x > exp_y:
        new_exp = exp_x
        diff = exp_x - exp_y
        
        if diff > 0:
            guard1 = (man_y_24 >> (diff - 1)) & 1
            if diff > 1:
                sticky_mask = (1 << (diff - 1)) - 1
                sticky1 = 1 if (man_y_24 & sticky_mask) > 0 else 0
        
        if diff >= 24:
            sm2 = 0
            guard1 = 0
            sticky1 = 1 if man_y_24 > 0 else 0
        else:
            sm2 = man_y_24 >> diff
    
    else: # exp_y > exp_x
        new_exp = exp_y
        diff = exp_y - exp_x

        if diff > 0 and diff <= 23:
             guard1 = (man_x >> (diff - 1)) & 1
        else:
             guard1 = 0
        
        if diff > 1:
            sticky_mask = (1 << (diff - 1)) - 1
            shifted_part = man_y_24 & sticky_mask
            sticky1 = 1 if shifted_part > 0 else 0
            
        if diff >= 24:
            sm1 = 0
            guard1 = 0
            sticky1 = 1 if man_x_24 > 0 else 0
        else:
            sm1 = man_x_24 >> diff

    # Add mantissas
    temp_sum_mantissa = sm1 + sm2
    man_carry = (temp_sum_mantissa >> 24) & 1
    final_mantissa = 0
    
    if man_carry == 1:
        guard2 = temp_sum_mantissa & 1
        sticky2 = guard1 | sticky1
        
        final_mantissa = (temp_sum_mantissa >> 1) & 0x7FFFFF
        
        # Rounding
        if guard2 == 1:
            if sticky2 == 1:
                final_mantissa += 1
            else:
                if (final_mantissa & 1) == 1:
                    final_mantissa += 1
    
    else:
        final_mantissa = temp_sum_mantissa & 0x7FFFFF
        
        # Rounding
        if guard1 == 1:
            if sticky1 == 1:
                final_mantissa += 1
            else:
                if (final_mantissa & 1) == 1:
                    final_mantissa += 1

    # Normalize
    if (final_mantissa & 0x800000):
        man_carry = 1
        final_mantissa = 0
        
    final_exp = new_exp + man_carry
    
    if final_exp >= 0xFF:
        return 0xFF800000 # Negative Infinity
    
    # Re-pack
    return (1 << 31) | (final_exp << 23) | (final_mantissa & 0x7FFFFF)

# File paths
a_path = "test-cases/huge/A.dat"
b_path = "test-cases/huge/B.dat"
n_path = "test-cases/huge/N.dat"
o_path = "test-cases/huge/input.dat"

# Load data
A = read_float32_data(a_path)
B = read_float32_data(b_path)
N, M = read_dimensions(n_path)
O = read_float32_data(o_path, 'raw')

A = A.reshape(N + 1, N)
B = B.reshape(N, M)

# Global variables
t = 0
curr = np.zeros(N, dtype=np.uint32)
temp = np.zeros(N, dtype=np.uint32)

max_obs_len = 64
bt = np.zeros((max_obs_len, N), dtype=np.int32)
path = np.zeros(max_obs_len, dtype=np.int32)
t_init = 0

def initialize(t):
    """Initialize Viterbi"""
    for j in range(N):
        obs_val = int(O[t], 16)
        if obs_val == 0:
            return -1
            
        curr[j] = summer_hw_emulation(A[0][j], B[j][obs_val - 1])
    return 0


def Viterbi():
    """Run Viterbi segment"""
    global t, curr, temp, bt, path, t_init

    init_ret = initialize(t)
    if init_ret == -1:
        return -1

    t += 1
    
    if O[t] == 'FFFFFFFF':
        t_init = t + 1
        t += 1
        return 0

    while O[t] != 'FFFFFFFF':
        obs_val = int(O[t], 16)
        if obs_val == 0:
             return -1

        for j in range(N):
            max_val = 0xFF800000 # Negative Infinity
            max_state = -1
            
            for i in range(N):
                val = summer_hw_emulation(curr[i], A[i + 1][j])
                val = summer_hw_emulation(val, B[j][obs_val - 1])

                if val < max_val:
                    max_val = val
                    max_state = i

            temp[j] = max_val
            if (t - t_init) < max_obs_len:
                 bt[t - t_init][j] = max_state

        curr, temp = temp, curr
        t += 1
        
        if (t - t_init) >= max_obs_len and O[t] != 'FFFFFFFF':
            print("Error: Sequence length exceeds max_obs_len of 64")
            while O[t] != 'FFFFFFFF' and O[t] != '00000000':
                t += 1
            if O[t] == 'FFFFFFFF':
                t += 1
            t_init = t
            return 0

    
    # Backtracking
    vprob = 0xFF800000
    final_time_index = t - t_init - 1

    for i in range(N):
        if curr[i] < vprob:
            vprob = curr[i]
            path[final_time_index] = i + 1

    for t_new in range(final_time_index - 1, -1, -1):
        next_state_idx = path[t_new + 1] - 1
        bt_time_idx = t_new + 1
        path[t_new] = bt[bt_time_idx][next_state_idx] + 1

    # Print results
    for i in range(0, final_time_index + 1):
        print(f"{path[i]:08x}")
        file.write(f"{path[i]:08x}\n")
    
    vprob_hex = f"{vprob:08x}"

    print(vprob_hex.lower())
    file.write(vprob_hex.lower() + "\n")

    t_init = t + 1
    t += 1

    print("ffffffff")
    file.write("ffffffff\n")

    return 0


# Main loop
file = open("output_python.dat", "w")
while Viterbi() != -1:
    path = np.zeros(max_obs_len, dtype=np.int32)
    pass
else:
    print("00000000")
    file.write("00000000\n")
    file.close()