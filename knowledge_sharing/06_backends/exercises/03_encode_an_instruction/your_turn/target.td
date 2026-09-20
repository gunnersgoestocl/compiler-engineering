// Build entry point for your_turn/. Order matters: the registers and the ALU
// class must exist before instrinfo.td uses them, and the Target record in
// epilogue.td must come after the instructions exist.
include "common.td"
include "your_turn/instrinfo.td"
include "epilogue.td"
