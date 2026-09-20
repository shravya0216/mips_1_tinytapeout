`timescale 1ns / 1ps

module BTB(
    input clk,
    input [3:0] rd_addr,
    input BTB_write_control,
    input [3:0] ID_EX_PHT_wr_addr,
    input [31:0] BTB_write_data,
    input rst,
    output [31:0] BTB_rd_data
);

    // Original:
    // reg [31:0] BTB [15:0];
    //
    // 16 entries x 32 bits = 512 bits.
    //
    // Packed representation:
    // BTB[31:0]     = original BTB[0]
    // BTB[63:32]    = original BTB[1]
    // ...
    // BTB[511:480]  = original BTB[15]

    reg [511:0] BTB;

    // Equivalent to:
    // assign BTB_rd_data = BTB[rd_addr];
    //
    // Select the 32-bit entry corresponding to rd_addr.
    assign BTB_rd_data = BTB[rd_addr * 32 +: 32];

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            BTB <= 512'b0;
        end
        else if (BTB_write_control)
        begin
            BTB[ID_EX_PHT_wr_addr * 32 +: 32] <= BTB_write_data;
        end
    end

endmodule
