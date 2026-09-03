#------------------------------------------------------------------------------
# Project Name      :   YBT_FPGA_SSTMC
# Script Name       :   Do.tcl
# Description       :   MathCore 模块级仿真脚本（ModelSim / Questa，VHDL-2008）
# Usage             :
#   cd <...>/module/Simulation/MathCoreTb/Script
#   vsim -do Do.tcl
#   或仅跑某一 TB： set ::MATHCORE_TB signed_division_tb; do Do.tcl
#------------------------------------------------------------------------------

if {![info exists ::MATHCORE_TB]} {
    # 可选: signed_division_tb | unsigned_division_tb | mult_axb_tb |
    #       signed_div100_16bit_tb | division100_16bit_tb |
    #       cube_root_newton_tb | cube_root_iter_tb | sqrt_core_tb | all
    set ::MATHCORE_TB all
}

set RTL_DIR   [file normalize "../../../Core/MathCore"]
set BENCH_DIR [file normalize "../Bench"]
set WORK_DIR  [file normalize "../work"]

file mkdir $WORK_DIR
cd $WORK_DIR

puts "=========================================="
puts "MathCoreTb Simulation (VHDL-2008)"
puts "TB select: $::MATHCORE_TB"
puts "=========================================="

# 清理并建库
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# -------------------- 编译 RTL（依赖顺序） --------------------
set rtl_files [list \
    signed_division.vhd \
    unsigned_division.vhd \
    mult_axb.vhd \
    signed_div100_16bit.vhd \
    division100_16bit.vhd \
    cube_root_newton.vhd \
    cube_root_iter.vhd \
    sqrt_core.vhd \
]

foreach f $rtl_files {
    set path [file join $RTL_DIR $f]
    puts "Analyze RTL: $path"
    vcom -2008 -work work $path
}

# -------------------- 编译 TB --------------------
set all_tbs [list \
    signed_division_tb \
    unsigned_division_tb \
    mult_axb_tb \
    signed_div100_16bit_tb \
    division100_16bit_tb \
    cube_root_newton_tb \
    cube_root_iter_tb \
    sqrt_core_tb \
]

if {$::MATHCORE_TB eq "all"} {
    set run_list $all_tbs
} else {
    set run_list [list $::MATHCORE_TB]
}

foreach tb $run_list {
    set tb_path [file join $BENCH_DIR ${tb}.vhd]
    puts "Analyze TB: $tb_path"
    vcom -2008 -work work $tb_path
}

# -------------------- 逐个仿真 --------------------
foreach tb $run_list {
    puts "------------------------------------------"
    puts "Run: $tb"
    puts "------------------------------------------"
    vsim -t 1ps -voptargs=+acc work.$tb
    # 需要波形时取消下一行注释
    # add wave -r /*
    run -all
    quit -sim
}

puts "=========================================="
puts "MathCoreTb 全部仿真结束"
puts "=========================================="
quit -f
