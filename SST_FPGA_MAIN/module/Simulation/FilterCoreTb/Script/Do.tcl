# FilterCore ModelSim script (VHDL-2008)
# cd module/Simulation/FilterCoreTb/Script
# vsim -do Do.tcl

set RTL_DIR    [file normalize "../../../Core/FilterCore"]
set MATH_DIR   [file normalize "../../../Core/MathCore"]
set BENCH_DIR  [file normalize "../Bench"]
set WORK_DIR   [file normalize "../work"]

file mkdir $WORK_DIR
cd $WORK_DIR

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# MathCore dependency for lpf_core
vcom -2008 -work work [file join $MATH_DIR signed_division.vhd]

foreach f {
    lpf_tustin.vhd
    lpf_tustin_auto_ctrl.vhd
    lpf_core.vhd
    filter_core.vhd
    low_speed_filter_core.vhd
} {
    vcom -2008 -work work [file join $RTL_DIR $f]
}

vcom -2008 -work work [file join $BENCH_DIR lpf_tustin_tb.vhd]

vsim -t 1ps -voptargs=+acc work.lpf_tustin_tb
run -all
quit -f
