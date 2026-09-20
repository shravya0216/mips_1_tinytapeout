`timescale 1ns / 1ps

module instruction_memory(
    input        rst,
    input        clk,
    input [31:0] PC_out,
    output [31:0] instruction_code,
    input        prog_we,
    input [7:0]  prog_addr,
    input [31:0] prog_wdata,
    output [31:0] prog_rdata
);
    // Packed equivalent of the original 1024-entry x 8-bit byte memory.
    reg [8191:0] IM;

    assign instruction_code = {
        IM[PC_out[9:0] * 8 +: 8],
        IM[(PC_out[9:0] + 10'd1) * 8 +: 8],
        IM[(PC_out[9:0] + 10'd2) * 8 +: 8],
        IM[(PC_out[9:0] + 10'd3) * 8 +: 8]
    };

    assign prog_rdata = {
        IM[{prog_addr,2'b00} * 8 +: 8],
        IM[({prog_addr,2'b00} + 10'd1) * 8 +: 8],
        IM[({prog_addr,2'b00} + 10'd2) * 8 +: 8],
        IM[({prog_addr,2'b00} + 10'd3) * 8 +: 8]
    };

    always @(posedge clk) begin
        if (prog_we) begin
            IM[{prog_addr,2'b00} * 8 +: 8] <= prog_wdata[31:24];
            IM[({prog_addr,2'b00} + 10'd1) * 8 +: 8] <= prog_wdata[23:16];
            IM[({prog_addr,2'b00} + 10'd2) * 8 +: 8] <= prog_wdata[15:8];
            IM[({prog_addr,2'b00} + 10'd3) * 8 +: 8] <= prog_wdata[7:0];
        end
    end
endmodule
