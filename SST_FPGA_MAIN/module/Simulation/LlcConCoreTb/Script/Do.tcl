# LlcConCore ModelSim script (VHDL-2008)
# cd module/Simulation/LlcConCoreTb/Script
# vsim -do Do.tcl

set RTL_DIR   [file normalize "../../../Core/LlcConCore"]
set BENCH_DIR [file normalize "../Bench"]
set WORK_DIR  [file normalize "../work"]

file mkdir $WORK_DIR
cd $WORK_DIR

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

foreach f {
    vo_ma_filter.vhd
    llc_ramp.vhd
    llc_period_pi.vhd
    llc_con_core.vhd
} {
    vcom -2008 -work work [file join $RTL_DIR $f]
}
vcom -2008 -work work [file join $BENCH_DIR llc_con_core_tb.vhd]

vsim -t 1ps -voptargs=+acc work.llc_con_core_tb
run -all
quit -f
