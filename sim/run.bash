#!/bin/bash

set -e

# Compile DPI C++ model
g++ -fPIC -shared \
    -I"$RIVIERA_HOME/interfaces/include" \
    -o apb_c_model.so \
    apb_c_model.cpp

# Compile SV/UVM
vlib work

vlog -timescale 1ns/1ns \
    +incdir+$RIVIERA_HOME/vlib/uvm-1.2/src \
    +incdir+. \
    -l uvm_1_2 \
    design.sv testbench.sv

# Run simulation
vsim -c -do run.do