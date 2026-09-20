`timescale 1ns / 1ps

// Exhaustive-program testbench for the supplied instruction sequence.
//
// Tests the exact program from instruction_memory.v through the CURRENT
// I2C/MMIO-programmable top:
//   - programs DM[7], DM[20], DM[21]
//   - programs every instruction word 0x00..0x84
//   - programs TARGET_PC = 0x7C
//   - verifies LOAD mode is frozen
//   - starts RUN through CSR[0]
//   - verifies the complete architectural result
//   - verifies the TARGET instruction/end marker is not executed
//
// I2C frame:
//   START + 0x84 + addr[15:8] + addr[7:0] + data[31:24] +
//   data[23:16] + data[15:8] + data[7:0] + STOP
//
// IMPORTANT:
// This TB assumes the same hierarchy as the current integrated top:
//   dut.IM_inst.IM[]
//   dut.REGFILE_inst.RF[]
//   dut.DM_inst.DM[]
//   dut.PC_out
//   dut.target_pc
//   dut.run_req
//   dut.done
//   dut.LED
//
// If your top's LED port is named differently, change only the LED wire
// connection below.

module tb_top_i2c_mips_exhaustive;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg scl = 1'b1;
    tri sda;
    pullup(sda);

    // 1 = release SDA, 0 = pull SDA low.
    reg sda_drive = 1'b1;
    assign sda = sda_drive ? 1'bz : 1'b0;

    wire led;

    top dut (
        .clk(clk),
        .rst(rst),
        .scl(scl),
        .sda(sda),
        .led(led)
    );

    integer errors;
    integer i;

    // 100 MHz system clock.
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // EXACT instruction words supplied in instruction_memory.v
    // Word index = byte address / 4.
    // ------------------------------------------------------------------------
    reg [31:0] program [0:33];

    initial begin
        program[0]  = 32'h08100007; // 0x00 ADDI R16,$0,7
        program[1]  = 32'h0E110000; // 0x04 LW   R17,0(R16)
        program[2]  = 32'h02319000; // 0x08 ADD  R18,R17,R17
        program[3]  = 32'h08150014; // 0x0C ADDI R21,$0,20
        program[4]  = 32'h0EB60000; // 0x10 LW   R22,0(R21)
        program[5]  = 32'h02D6B800; // 0x14 ADD  R23,R22,R22
        program[6]  = 32'h08180015; // 0x18 ADDI R24,$0,21
        program[7]  = 32'h0F190000; // 0x1C LW   R25,0(R24)
        program[8]  = 32'h0339D000; // 0x20 ADD  R26,R25,R25
        program[9]  = 32'h081B0005; // 0x24 ADDI R27,$0,5
        program[10] = 32'h037BE000; // 0x28 ADD  R28,R27,R27
        program[11] = 32'h081C0003; // 0x2C ADDI R28,$0,3
        program[12] = 32'h0380E800; // 0x30 ADD  R29,R28,$0
        program[13] = 32'h081E0309; // 0x34 ADDI R30,$0,777
        program[14] = 32'h0000F000; // 0x38 ADD  R30,$0,$0
        program[15] = 32'h08130000; // 0x3C ADDI R19,$0,0
        program[16] = 32'h16600001; // 0x40 BEQ  R19,$0,+1
        program[17] = 32'h14000000; // 0x44 BEQ  $0,$0,+0 (dead)
        program[18] = 32'h081F0000; // 0x48 ADDI R31,$0,0
        program[19] = 32'h17E00002; // 0x4C BEQ  R31,$0,+2
        program[20] = 32'h0810022B; // 0x50 ADDI R16,$0,555 (poison)
        program[21] = 32'h0811022C; // 0x54 ADDI R17,$0,556 (poison)
        program[22] = 32'h14000001; // 0x58 BEQ  $0,$0,+1
        program[23] = 32'h0812022D; // 0x5C ADDI R18,$0,557 (poison)
        program[24] = 32'h08080008; // 0x60 ADDI R8,$0,8
        program[25] = 32'h08090000; // 0x64 ADDI R9,$0,0
        program[26] = 32'h01284800; // 0x68 ADD  R9,R9,R8
        program[27] = 32'h0908FFFF; // 0x6C ADDI R8,R8,-1
        program[28] = 32'h15000001; // 0x70 BEQ  R8,$0,+1
        program[29] = 32'h1400FFFC; // 0x74 BEQ  $0,$0,-4
        program[30] = 32'h10090000; // 0x78 SW   R9,0($0)
        program[31] = 32'hFC000000; // 0x7C end marker
        program[32] = 32'hFC000000; // 0x80 end marker
        program[33] = 32'hFC000000; // 0x84 end marker
    end

    // ------------------------------------------------------------------------
    // I2C timing: 100 kHz.
    // ------------------------------------------------------------------------
    task scl_low;
        begin
            scl = 1'b0;
            #5000;
        end
    endtask

    task scl_high;
        begin
            scl = 1'b1;
            #5000;
        end
    endtask

    task i2c_start;
        begin
            sda_drive = 1'b1;
            scl = 1'b1;
            #5000;

            sda_drive = 1'b0;
            #5000;

            scl = 1'b0;
            #5000;
        end
    endtask

    task i2c_stop;
        begin
            sda_drive = 1'b0;
            scl = 1'b0;
            #5000;

            scl = 1'b1;
            #5000;

            sda_drive = 1'b1;
            #5000;
        end
    endtask

    task i2c_write_bit;
        input b;
        begin
            scl = 1'b0;
            sda_drive = b ? 1'b1 : 1'b0;
            #5000;

            scl = 1'b1;
            #5000;
        end
    endtask

    task i2c_ack_bit;
        begin
            // Release SDA so the slave can ACK by pulling it low.
            scl = 1'b0;
            sda_drive = 1'b1;
            #5000;

            scl = 1'b1;
            #2500;

            if (sda !== 1'b0) begin
                $display("FAIL @ %0t: I2C ACK missing, SDA=%b", $time, sda);
                errors = errors + 1;
            end

            #2500;
            scl = 1'b0;
            #5000;
        end
    endtask

    task i2c_write_byte;
        input [7:0] b;
        integer k;
        begin
            for (k = 7; k >= 0; k = k - 1)
                i2c_write_bit(b[k]);

            i2c_ack_bit;
        end
    endtask

    // One complete MMIO write.
    task mmio_write;
        input [15:0] addr;
        input [31:0] data;
        begin
            i2c_start;

            i2c_write_byte(8'h84);       // slave 0x42 + write
            i2c_write_byte(addr[15:8]);
            i2c_write_byte(addr[7:0]);
            i2c_write_byte(data[31:24]);
            i2c_write_byte(data[23:16]);
            i2c_write_byte(data[15:8]);
            i2c_write_byte(data[7:0]);

            i2c_stop;

            // Give the synchronous MMIO destination time to see mmio_wr.
            #100;
        end
    endtask

    // ------------------------------------------------------------------------
    // Check helpers.
    // ------------------------------------------------------------------------
    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("FAIL @ %0t: %0s actual=%h expected=%h",
                         $time, name, actual, expected);
                errors = errors + 1;
            end
            else begin
                $display("PASS @ %0t: %0s = %h", $time, name, actual);
            end
        end
    endtask

    task check1;
        input actual;
        input expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("FAIL @ %0t: %0s actual=%b expected=%b",
                         $time, name, actual, expected);
                errors = errors + 1;
            end
            else begin
                $display("PASS @ %0t: %0s = %b", $time, name, actual);
            end
        end
    endtask

    task check_imem_word;
        input integer word_index;
        input [31:0] expected;
        reg [31:0] actual;
        begin
            actual = {
                dut.IM_inst.IM[((word_index*4)+0) * 8 +: 8],
                dut.IM_inst.IM[((word_index*4)+1) * 8 +: 8],
                dut.IM_inst.IM[((word_index*4)+2) * 8 +: 8],
                dut.IM_inst.IM[((word_index*4)+3) * 8 +: 8]
            };

            if (actual !== expected) begin
                $display("FAIL @ %0t: IMEM[%02h] actual=%h expected=%h",
                         $time, word_index*4, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main test.
    // ------------------------------------------------------------------------
    initial begin
        errors = 0;
        sda_drive = 1'b1;

        $display("");
        $display("============================================================");
        $display(" EXHAUSTIVE MIPS + I2C/MMIO TEST");
        $display(" Supplied instruction sequence: 0x00 through 0x84");
        $display(" TARGET_PC = 0x7C");
        $display("============================================================");
        $display("");

        // Reset.
        #100;
        rst = 1'b0;
        #100;

        // ------------------------------------------------------------
        // Reset / LOAD-mode checks.
        // ------------------------------------------------------------
        check32(dut.PC_out, 32'h00000000, "PC after reset");
        check1(dut.run_req, 1'b0, "RUN after reset");
        check1(dut.done, 1'b0, "DONE after reset");

        // ------------------------------------------------------------
        // Program the data needed by the exact supplied program.
        //
        // CPU load addresses are word indexed in the current design:
        //   LW R17,0(R16), R16=7  -> DM[7]
        //   LW R22,0(R21), R21=20 -> DM[20]
        //   LW R25,0(R24), R24=21 -> DM[21]
        // ------------------------------------------------------------
        mmio_write(16'h201C, 32'd7);    // DM[7]  = 7
        mmio_write(16'h2050, 32'd20);   // DM[20] = 20
        mmio_write(16'h2054, 32'd21);   // DM[21] = 21

        // ------------------------------------------------------------
        // Program ALL 34 instruction words through I2C.
        // IMEM byte address = MMIO address.
        // ------------------------------------------------------------
        for (i = 0; i <= 33; i = i + 1)
            mmio_write(i * 16'd4, program[i]);

        // Stop at the first end-marker instruction.
        // 0x7C itself must never execute.
        mmio_write(16'h3004, 32'h0000007C);

        // ------------------------------------------------------------
        // Verify the complete programmed image while still in LOAD.
        // ------------------------------------------------------------
        $display("");
        $display("Checking programmed instruction memory...");

        for (i = 0; i <= 33; i = i + 1)
            check_imem_word(i, program[i]);

        check32(dut.DM_inst.DM[(7) * 32 +: 32],  32'd7,  "DM[7] programmed");
        check32(dut.DM_inst.DM[(20) * 32 +: 32], 32'd20, "DM[20] programmed");
        check32(dut.DM_inst.DM[(21) * 32 +: 32], 32'd21, "DM[21] programmed");
        check32(dut.target_pc, 32'h0000007C, "TARGET_PC");

        // ------------------------------------------------------------
        // The CPU MUST still be completely frozen.
        // ------------------------------------------------------------
        check32(dut.PC_out, 32'h00000000, "PC still 0 in LOAD");
        check1(dut.run_req, 1'b0, "RUN still 0 in LOAD");
        check1(dut.done, 1'b0, "DONE still 0 in LOAD");

        // Architectural registers must still have reset values.
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd16, "R16 unchanged in LOAD");
        check32(dut.REGFILE_inst.RF[(17) * 32 +: 32], 32'd17, "R17 unchanged in LOAD");
        check32(dut.REGFILE_inst.RF[(9) * 32 +: 32],  32'd9,  "R9 unchanged in LOAD");

        // Wait many cycles and make sure LOAD remains frozen.
        repeat (20) @(posedge clk);

        check32(dut.PC_out, 32'h00000000, "PC remains frozen in LOAD");
        check1(dut.done, 1'b0, "DONE remains 0 in LOAD");
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd16, "R16 remains reset in LOAD");
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'd0, "DM[0] unchanged before RUN");

        // ------------------------------------------------------------
        // Start RUN.
        // ------------------------------------------------------------
        mmio_write(16'h3000, 32'h00000001);

        check1(dut.run_req, 1'b1, "RUN after start");

        // ------------------------------------------------------------
        // Wait for TARGET_PC/DONE.
        // The program is intentionally branch-heavy, so give it a
        // generous timeout.
        // ------------------------------------------------------------
        for (i = 0; i < 1000; i = i + 1) begin
            @(posedge clk);
            if (dut.done)
                i = 1000;
        end

        // ------------------------------------------------------------
        // Final architectural checks.
        // These are the expected results of the exact supplied program.
        // ------------------------------------------------------------
        $display("");
        $display("============================================================");
        $display(" FINAL ARCHITECTURAL CHECKS");
        $display("============================================================");

        check1(dut.done, 1'b1, "DONE");
        check1(led, 1'b1, "LED");
        check32(dut.PC_out, 32'h0000007C, "PC stopped at TARGET_PC");

        // Main expected results.
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd7,  "R16 = 7");
        check32(dut.REGFILE_inst.RF[(17) * 32 +: 32], 32'd7,  "R17 = 7");
        check32(dut.REGFILE_inst.RF[(18) * 32 +: 32], 32'd14, "R18 = 14");

        check32(dut.REGFILE_inst.RF[(21) * 32 +: 32], 32'd20, "R21 = 20");
        check32(dut.REGFILE_inst.RF[(22) * 32 +: 32], 32'd20, "R22 = 20");
        check32(dut.REGFILE_inst.RF[(23) * 32 +: 32], 32'd40, "R23 = 40");

        check32(dut.REGFILE_inst.RF[(24) * 32 +: 32], 32'd21, "R24 = 21");
        check32(dut.REGFILE_inst.RF[(25) * 32 +: 32], 32'd21, "R25 = 21");
        check32(dut.REGFILE_inst.RF[(26) * 32 +: 32], 32'd42, "R26 = 42");

        check32(dut.REGFILE_inst.RF[(27) * 32 +: 32], 32'd5, "R27 = 5");
        check32(dut.REGFILE_inst.RF[(28) * 32 +: 32], 32'd3, "R28 = 3");
        check32(dut.REGFILE_inst.RF[(29) * 32 +: 32], 32'd3, "R29 = 3 (forwarding priority)");

        // R30 must end at zero because the ADDI 777 is overwritten by
        // ADD R30,$0,$0.
        check32(dut.REGFILE_inst.RF[(30) * 32 +: 32], 32'd0, "R30 = 0");

        // Branch/loop registers.
        check32(dut.REGFILE_inst.RF[(19) * 32 +: 32], 32'd0, "R19 = 0");
        check32(dut.REGFILE_inst.RF[(31) * 32 +: 32], 32'd0, "R31 = 0");
        check32(dut.REGFILE_inst.RF[(8) * 32 +: 32],  32'd0, "R8 = 0");
        check32(dut.REGFILE_inst.RF[(9) * 32 +: 32],  32'd36, "R9 = 36");

        // Poison instructions must have been squashed.
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd7, "R16 poison instruction not executed");
        check32(dut.REGFILE_inst.RF[(17) * 32 +: 32], 32'd7, "R17 poison instruction not executed");
        check32(dut.REGFILE_inst.RF[(18) * 32 +: 32], 32'd14, "R18 poison instruction not executed");

        // Reset-only registers should retain their reset values.
        check32(dut.REGFILE_inst.RF[(10) * 32 +: 32], 32'd10, "R10 unchanged");
        check32(dut.REGFILE_inst.RF[(11) * 32 +: 32], 32'd11, "R11 unchanged");
        check32(dut.REGFILE_inst.RF[(12) * 32 +: 32], 32'd12, "R12 unchanged");
        check32(dut.REGFILE_inst.RF[(13) * 32 +: 32], 32'd13, "R13 unchanged");
        check32(dut.REGFILE_inst.RF[(14) * 32 +: 32], 32'd14, "R14 unchanged");
        check32(dut.REGFILE_inst.RF[(15) * 32 +: 32], 32'd15, "R15 unchanged");

        // R0 must remain zero.
        check32(dut.REGFILE_inst.RF[(0) * 32 +: 32], 32'd0, "R0 protected");

        // Data-memory result.
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'd36, "DM[0] = loop sum 36");

        // The program's source data must remain intact.
        check32(dut.DM_inst.DM[(7) * 32 +: 32],  32'd7,  "DM[7] intact");
        check32(dut.DM_inst.DM[(20) * 32 +: 32], 32'd20, "DM[20] intact");
        check32(dut.DM_inst.DM[(21) * 32 +: 32], 32'd21, "DM[21] intact");

        // ------------------------------------------------------------
        // Predictor checks for the four guaranteed one-shot branches.
        // BHT/BTB are 16 entries indexed by PC[5:2].
        //
        // X1 @0x40 -> index 0 -> taken, target 0x48
        // X2 @0x44 -> index 1 -> must NOT train because it is squashed
        // Y1 @0x4C -> index 3 -> taken, target 0x58
        // Y2 @0x58 -> index 6 -> taken, target 0x60
        //
        // Loop predictor entries are intentionally not checked here because
        // the supplied program explicitly allows their trained-index drift.
        // ------------------------------------------------------------
        $display("");
        $display("Checking guaranteed one-shot predictor entries...");

        check1(dut.BHT_inst.BHT[0], 1'b1, "BHT[0] X1 taken");
        check32(dut.BTB_inst.BTB[(0) * 32 +: 32], 32'h00000048, "BTB[0] X1 target");

        check1(dut.BHT_inst.BHT[1], 1'b0, "BHT[1] X2 not trained");
        check32(dut.BTB_inst.BTB[(1) * 32 +: 32], 32'h00000000, "BTB[1] X2 not trained");

        check1(dut.BHT_inst.BHT[3], 1'b1, "BHT[3] Y1 taken");
        check32(dut.BTB_inst.BTB[(3) * 32 +: 32], 32'h00000058, "BTB[3] Y1 target");

        check1(dut.BHT_inst.BHT[6], 1'b1, "BHT[6] Y2 taken");
        check32(dut.BTB_inst.BTB[(6) * 32 +: 32], 32'h00000060, "BTB[6] Y2 target");

        // ------------------------------------------------------------
        // Summary.
        // ------------------------------------------------------------
        $display("");
        $display("============================================================");

        if (errors == 0) begin
            $display(" EXHAUSTIVE MIPS PROGRAM TEST: PASS");
            $display(" All supplied instructions executed correctly.");
            $display(" Load-use hazards, forwarding priority, branch flushing,");
            $display(" trained prediction, loop execution, SW and TARGET_PC");
            $display(" behavior all produced the expected architectural result.");
        end
        else begin
            $display(" EXHAUSTIVE MIPS PROGRAM TEST: FAIL");
            $display(" Total errors = %0d", errors);
        end

        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
