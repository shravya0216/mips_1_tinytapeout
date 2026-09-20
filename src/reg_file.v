`timescale 1ns / 1ps

module reg_file(
    input        clk,
    input        rst,
    input [4:0]  rs,
    input [4:0]  rt,
    input [4:0]  rd,
    input [31:0] write_data,
    input        Reg_write,
    output [31:0] D_1,
    output [31:0] D_2,
    input        prog_we,
    input [4:0]  prog_addr,
    input [31:0] prog_wdata,
    output [31:0] prog_rdata
);
    integer i;

    // Same logical storage as the original 32-entry x 32-bit array.
    // Entry N occupies bits (N*32) through (N*32+31).
    reg [1023:0] RF;

    assign D_1 = (Reg_write && (rd == rs) && (rd != 5'd0)) ? write_data : RF[rs * 32 +: 32];
    assign D_2 = (Reg_write && (rd == rt) && (rd != 5'd0)) ? write_data : RF[rt * 32 +: 32];

    // I2C readback of register prog_addr.
    assign prog_rdata = RF[prog_addr * 32 +: 32];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i <= 31; i = i + 1)
                RF[i * 32 +: 32] <= i;
        end else begin
            if (prog_we && (prog_addr != 5'd0))
                RF[prog_addr * 32 +: 32] <= prog_wdata;
            else if (Reg_write && rd != 5'd0)
                RF[rd * 32 +: 32] <= write_data;
        end
    end
endmodule
