`timescale 1ns / 1ps

// 256 x 32-bit data memory.
// CPU addressing remains WORD-indexed to preserve the existing MIPS program:
// LW/SW address 7 accesses DM[7], address 20 accesses DM[20], etc.
module data_memory(
    input        clk,
    input        rst,
    input        Mem_rd,
    input        Mem_write,
    input [31:0] rd_addr,
    input [31:0] write_data,
    output reg [31:0] rd_data,
    input        prog_we,
    input [7:0]  prog_addr,
    input [31:0] prog_wdata,
    output [31:0] prog_rdata
);
    integer i;

    // Same logical storage as the original 256-entry x 32-bit array.
    // Entry N occupies bits (N*32) through (N*32+31).
    reg [8191:0] DM;

    // I2C readback of DM[prog_addr].
    assign prog_rdata = DM[prog_addr * 32 +: 32];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i <= 255; i = i + 1)
                DM[i * 32 +: 32] <= 32'd0;
        end else begin
            if (Mem_write)
                DM[rd_addr[7:0] * 32 +: 32] <= write_data;
            if (prog_we)
                DM[prog_addr * 32 +: 32] <= prog_wdata;
        end
    end

    always @(*) begin
        if (Mem_rd)
            rd_data = DM[rd_addr[7:0] * 32 +: 32];
        else
            rd_data = 32'b0;
    end
endmodule
