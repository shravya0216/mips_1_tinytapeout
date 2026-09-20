`timescale 1ns / 1ps

module PHT(
    input clk,
    input [3:0] rd_addr,
    input PHT_write_control,
    input [3:0] ID_EX_PHT_wr_addr,
    input PHT_write_data,
    input rst,
    output [3:0] PHT_rd_data
);

    // Original storage:
    //
    // reg [3:0] PHT [15:0];
    //
    // = 16 entries x 4 bits
    // = 64 bits of total state.
    //
    // We represent the same 64 bits as four packed 16-bit vectors.
    //
    // PHT_bit0[address] = original PHT[address][0]
    // PHT_bit1[address] = original PHT[address][1]
    // PHT_bit2[address] = original PHT[address][2]
    // PHT_bit3[address] = original PHT[address][3]

    reg [15:0] PHT_bit0;
    reg [15:0] PHT_bit1;
    reg [15:0] PHT_bit2;
    reg [15:0] PHT_bit3;

    // Same read operation as:
    //
    // assign PHT_rd_data = PHT[rd_addr];

    assign PHT_rd_data[0] = PHT_bit0[rd_addr];
    assign PHT_rd_data[1] = PHT_bit1[rd_addr];
    assign PHT_rd_data[2] = PHT_bit2[rd_addr];
    assign PHT_rd_data[3] = PHT_bit3[rd_addr];

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            PHT_bit0 <= 16'b0;
            PHT_bit1 <= 16'b0;
            PHT_bit2 <= 16'b0;
            PHT_bit3 <= 16'b0;
        end
        else if (PHT_write_control)
        begin
            // Original:
            //
            // PHT[index] <= {
            //     PHT[index][2],
            //     PHT[index][1],
            //     PHT[index][0],
            //     PHT_write_data
            // };
            //
            // Because these are nonblocking assignments, all RHS
            // values come from the OLD state.

            PHT_bit3[ID_EX_PHT_wr_addr] <=
                PHT_bit2[ID_EX_PHT_wr_addr];

            PHT_bit2[ID_EX_PHT_wr_addr] <=
                PHT_bit1[ID_EX_PHT_wr_addr];

            PHT_bit1[ID_EX_PHT_wr_addr] <=
                PHT_bit0[ID_EX_PHT_wr_addr];

            PHT_bit0[ID_EX_PHT_wr_addr] <=
                PHT_write_data;
        end
    end

endmodule
