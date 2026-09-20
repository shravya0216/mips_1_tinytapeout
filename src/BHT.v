/*`timescale 1ns / 1ps

module BHT(
input clk,
input [3:0] rd_addr,
input BHT_write_control,
input [3:0] ID_EX_BHT_wr_addr,
input BHT_write_data,
input rst,
output  BHT_rd_data
    );
    integer i;
    reg BHT [15:0];
    assign BHT_rd_data = BHT[rd_addr];
    always @ (posedge clk or posedge rst)
    begin
    if(rst)
    begin
    for(i=0;i<=15;i=i+1)
    BHT[i]<=1'b0;
    end
    else if (BHT_write_control)
    begin
    BHT[ID_EX_BHT_wr_addr]<=BHT_write_data;
    end
    end
endmodule*/
`timescale 1ns / 1ps

module BHT(
    input clk,
    input [3:0] rd_addr,
    input BHT_write_control,
    input [3:0] ID_EX_BHT_wr_addr,
    input BHT_write_data,
    input rst,
    output BHT_rd_data
);

    // Original:
    // reg BHT [15:0];
    //
    // This represented 16 independent 1-bit storage elements.
    // The packed representation below contains exactly the same
    // 16 bits of state, but avoids the unpacked-array construct.

    reg [15:0] BHT;

    // Same read behavior as:
    // assign BHT_rd_data = BHT[rd_addr];
    assign BHT_rd_data = BHT[rd_addr];

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            BHT <= 16'b0;
        end
        else if (BHT_write_control)
        begin
            BHT[ID_EX_BHT_wr_addr] <= BHT_write_data;
        end
    end

endmodule

