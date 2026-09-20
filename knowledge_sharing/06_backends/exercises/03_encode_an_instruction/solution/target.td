// Build entry point for solution/. Order matters: the registers and the ALU
// class must exist before instrinfo.td uses them, and the Target record in
// epilogue.td must come after the instructions exist.
include "common.td"
include "solution/instrinfo.td"
include "epilogue.td"
