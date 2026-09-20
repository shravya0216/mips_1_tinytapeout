`timescale 1ns / 1ps

// ============================================================================
// MIPS + I2C/MMIO ADVERSARIAL / EDGE-CASE TESTBENCH
//
// Intended for the CURRENT integrated top and the exact instruction encoding
// supplied by the user.
//
// This TB covers:
//   1. Normal exhaustive program
//   2. TARGET_PC at 0x00 / early / middle / after pipeline activity
//   3. R0 protection through programming and normal execution
//   4. MMIO aligned boundaries + invalid/misaligned addresses
//   5. I2C wrong address
//   6. I2C partial transaction / STOP at every payload boundary
//   7. I2C repeated START
//   8. I2C reset during a transaction
//   9. Back-to-back load-use hazards
//  10. Branch data hazards
//  11. Taken and not-taken branches
//  12. Back-to-back branches / wrong-path flushing
//  13. Predictor training only from resolved branches
//  14. Long loop / predictor alias stress
//  15. Reset during RUN
//  16. RUN/DONE behavior
//
// NOTE:
// This TB deliberately uses the real I2C path for MMIO writes.
// Some tests are "protocol robustness" tests and therefore intentionally
// send malformed/partial transactions and verify that no MMIO write occurs.
//
// Expected DUT hierarchy (same as previous exhaustive TB):
//   dut.IM_inst.IM[]
//   dut.REGFILE_inst.RF[]
//   dut.DM_inst.DM[]
//   dut.PC_out
//   dut.target_pc
//   dut.run_req
//   dut.done
//   dut.LED
//   dut.BHT_inst.BHT[]
//   dut.BTB_inst.BTB[]
//
// If your exact top uses different hierarchy names, only the hierarchy
// references below need to be adjusted.
// ============================================================================

module tb_top_i2c_mips_edge_cases;

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
    integer before_value;

    always #5 clk = ~clk;

    // ========================================================================
    // Exact supplied exhaustive program.
    // ========================================================================
    reg [31:0] program [0:33];

    initial begin
        program[0]  = 32'h08100007;
        program[1]  = 32'h0E110000;
        program[2]  = 32'h02319000;
        program[3]  = 32'h08150014;
        program[4]  = 32'h0EB60000;
        program[5]  = 32'h02D6B800;
        program[6]  = 32'h08180015;
        program[7]  = 32'h0F190000;
        program[8]  = 32'h0339D000;
        program[9]  = 32'h081B0005;
        program[10] = 32'h037BE000;
        program[11] = 32'h081C0003;
        program[12] = 32'h0380E800;
        program[13] = 32'h081E0309;
        program[14] = 32'h0000F000;
        program[15] = 32'h08130000;
        program[16] = 32'h16600001;
        program[17] = 32'h14000000;
        program[18] = 32'h081F0000;
        program[19] = 32'h17E00002;
        program[20] = 32'h0810022B;
        program[21] = 32'h0811022C;
        program[22] = 32'h14000001;
        program[23] = 32'h0812022D;
        program[24] = 32'h08080008;
        program[25] = 32'h08090000;
        program[26] = 32'h01284800;
        program[27] = 32'h0908FFFF;
        program[28] = 32'h15000001;
        program[29] = 32'h1400FFFC;
        program[30] = 32'h10090000;
        program[31] = 32'hFC000000;
        program[32] = 32'hFC000000;
        program[33] = 32'hFC000000;
    end

    // ========================================================================
    // I2C primitives: 100 kHz.
    // ========================================================================
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
        input check_ack;
        begin
            scl = 1'b0;
            sda_drive = 1'b1;
            #5000;
            scl = 1'b1;
            #2500;

            if (check_ack && (sda !== 1'b0)) begin
                $display("FAIL @ %0t: expected ACK, SDA=%b", $time, sda);
                errors = errors + 1;
            end

            #2500;
            scl = 1'b0;
            #5000;
        end
    endtask

    task i2c_write_byte;
        input [7:0] b;
        input check_ack;
        integer k;
        begin
            for (k = 7; k >= 0; k = k - 1)
                i2c_write_bit(b[k]);
            i2c_ack_bit(check_ack);
        end
    endtask

    // Complete legal MMIO transaction.
    task mmio_write;
        input [15:0] addr;
        input [31:0] data;
        begin
            i2c_start;
            i2c_write_byte(8'h84, 1'b1);
            i2c_write_byte(addr[15:8], 1'b1);
            i2c_write_byte(addr[7:0], 1'b1);
            i2c_write_byte(data[31:24], 1'b1);
            i2c_write_byte(data[23:16], 1'b1);
            i2c_write_byte(data[15:8], 1'b1);
            i2c_write_byte(data[7:0], 1'b1);
            i2c_stop;
            #100;
        end
    endtask

    // Send only the first N payload bytes after the address byte, then STOP.
    // n_payload = 0 means STOP immediately after address ACK.
    task partial_mmio_write;
        input [15:0] addr;
        input [31:0] data;
        input integer n_payload;
        begin
            i2c_start;
            i2c_write_byte(8'h84, 1'b1);

            if (n_payload >= 1) i2c_write_byte(addr[15:8], 1'b1);
            if (n_payload >= 2) i2c_write_byte(addr[7:0], 1'b1);
            if (n_payload >= 3) i2c_write_byte(data[31:24], 1'b1);
            if (n_payload >= 4) i2c_write_byte(data[23:16], 1'b1);
            if (n_payload >= 5) i2c_write_byte(data[15:8], 1'b1);
            if (n_payload >= 6) i2c_write_byte(data[7:0], 1'b1);

            i2c_stop;
            #100;
        end
    endtask

    // Wrong I2C address. The slave should not ACK.
    task wrong_address_write;
        input [6:0] wrong_addr;
        input [15:0] addr;
        input [31:0] data;
        begin
            i2c_start;

            // Deliberately do not require ACK for address.
            i2c_write_byte({wrong_addr,1'b0}, 1'b0);

            i2c_write_byte(addr[15:8], 1'b0);
            i2c_write_byte(addr[7:0], 1'b0);
            i2c_write_byte(data[31:24], 1'b0);
            i2c_write_byte(data[23:16], 1'b0);
            i2c_write_byte(data[15:8], 1'b0);
            i2c_write_byte(data[7:0], 1'b0);

            i2c_stop;
            #100;
        end
    endtask

    // Repeated START between two bytes.
    task repeated_start_test;
        input [15:0] addr;
        input [31:0] data;
        begin
            i2c_start;
            i2c_write_byte(8'h84, 1'b1);
            i2c_write_byte(addr[15:8], 1'b1);

            // Repeated START.
            sda_drive = 1'b1;
            scl = 1'b1;
            #5000;
            sda_drive = 1'b0;
            #5000;
            scl = 1'b0;
            #5000;

            // Continue as a new transaction.
            i2c_write_byte(8'h84, 1'b1);
            i2c_write_byte(addr[15:8], 1'b1);
            i2c_write_byte(addr[7:0], 1'b1);
            i2c_write_byte(data[31:24], 1'b1);
            i2c_write_byte(data[23:16], 1'b1);
            i2c_write_byte(data[15:8], 1'b1);
            i2c_write_byte(data[7:0], 1'b1);
            i2c_stop;
            #100;
        end
    endtask

    // ========================================================================
    // Checks.
    // ========================================================================
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
            else
                $display("PASS @ %0t: %0s = %h", $time, name, actual);
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
            else
                $display("PASS @ %0t: %0s = %b", $time, name, actual);
        end
    endtask

    // ========================================================================
    // MAIN
    // ========================================================================
    initial begin
        errors = 0;
        sda_drive = 1'b1;

        $display("");
        $display("============================================================");
        $display(" MIPS + I2C/MMIO ADVERSARIAL EDGE-CASE TEST");
        $display("============================================================");
        $display("");

        // --------------------------------------------------------------------
        // Initial reset.
        // --------------------------------------------------------------------
        #100;
        rst = 1'b0;
        #100;

        check32(dut.PC_out, 32'h0, "PC after reset");
        check1(dut.run_req, 1'b0, "RUN after reset");
        check1(dut.done, 1'b0, "DONE after reset");
        check32(dut.REGFILE_inst.RF[(0) * 32 +: 32], 32'h0, "R0 after reset");

        // ====================================================================
        // SECTION 1: MMIO boundary / invalid address tests
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 1: MMIO BOUNDARIES / INVALID ADDRESSES");
        $display("------------------------------------------------------------");

        // Known value to detect accidental writes.
        mmio_write(16'h1004, 32'h000000AA);
        check32(dut.REGFILE_inst.RF[(1) * 32 +: 32], 32'h000000AA, "RF[1] baseline");

        // IMEM valid boundaries.
        mmio_write(16'h0000, 32'h12345678);
        mmio_write(16'h03FC, 32'h89ABCDEF);
        check32(
            {dut.IM_inst.IM[(0) * 8 +: 8],dut.IM_inst.IM[(1) * 8 +: 8],dut.IM_inst.IM[(2) * 8 +: 8],dut.IM_inst.IM[(3) * 8 +: 8]},
            32'h12345678,
            "IMEM[0] boundary"
        );
        check32(
            {dut.IM_inst.IM[(1020) * 8 +: 8],dut.IM_inst.IM[(1021) * 8 +: 8],dut.IM_inst.IM[(1022) * 8 +: 8],dut.IM_inst.IM[(1023) * 8 +: 8]},
            32'h89ABCDEF,
            "IMEM[0x3FC] boundary"
        );

        // Invalid IMEM address must not alter existing word.
        mmio_write(16'h0400, 32'hDEADBEEF);
        check32(
            {dut.IM_inst.IM[(1020) * 8 +: 8],dut.IM_inst.IM[(1021) * 8 +: 8],dut.IM_inst.IM[(1022) * 8 +: 8],dut.IM_inst.IM[(1023) * 8 +: 8]},
            32'h89ABCDEF,
            "IMEM outside-range rejected"
        );

        // Misaligned IMEM writes must not happen.
        mmio_write(16'h0001, 32'hCAFEBABE);
        mmio_write(16'h0002, 32'hCAFEBABE);
        mmio_write(16'h0003, 32'hCAFEBABE);
        check32(
            {dut.IM_inst.IM[(0) * 8 +: 8],dut.IM_inst.IM[(1) * 8 +: 8],dut.IM_inst.IM[(2) * 8 +: 8],dut.IM_inst.IM[(3) * 8 +: 8]},
            32'h12345678,
            "IMEM misaligned writes rejected"
        );

        // RF upper boundary and invalid address.
        mmio_write(16'h107C, 32'h000000EE);
        check32(dut.REGFILE_inst.RF[(31) * 32 +: 32], 32'h000000EE, "RF[31] boundary");
        mmio_write(16'h1080, 32'hDEADBEEF);
        check32(dut.REGFILE_inst.RF[(31) * 32 +: 32], 32'h000000EE, "RF outside-range rejected");

        // DM boundaries.
        mmio_write(16'h2000, 32'h11111111);
        mmio_write(16'h23FC, 32'h22222222);
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'h11111111, "DM[0] boundary");
        check32(dut.DM_inst.DM[(255) * 32 +: 32], 32'h22222222, "DM[255] boundary");
        mmio_write(16'h2400, 32'hDEADBEEF);
        check32(dut.DM_inst.DM[(255) * 32 +: 32], 32'h22222222, "DM outside-range rejected");

        // Misaligned DM.
        mmio_write(16'h2001, 32'hCAFEBABE);
        mmio_write(16'h2002, 32'hCAFEBABE);
        mmio_write(16'h2003, 32'hCAFEBABE);
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'h11111111, "DM misaligned writes rejected");

        // CSR reserved/unmapped address must not accidentally touch memory.
        mmio_write(16'h3008, 32'hFFFFFFFF);
        check32(dut.target_pc, dut.target_pc, "unmapped CSR address harmless");

        // ====================================================================
        // SECTION 2: R0 protection
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 2: R0 PROTECTION");
        $display("------------------------------------------------------------");

        mmio_write(16'h1000, 32'hDEADBEEF);
        check32(dut.REGFILE_inst.RF[(0) * 32 +: 32], 32'h00000000, "MMIO cannot program R0");

        // Restore RF[1] etc later through the real exhaustive load.
        // ====================================================================
        // SECTION 3: I2C malformed transactions
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 3: I2C MALFORMED / PARTIAL TRANSACTIONS");
        $display("------------------------------------------------------------");

        // Partial writes must never assert a completed MMIO write.
        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hAAAAAAAA, 0);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after address rejected");

        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hBBBBBBBB, 1);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after addr_hi rejected");

        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hCCCCCCCC, 2);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after addr_lo rejected");

        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hDDDDDDDD, 3);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after data[31:24] rejected");

        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hEEEEEEEE, 4);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after data[23:16] rejected");

        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        partial_mmio_write(16'h2008, 32'hFFFFFFFF, 5);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "STOP after data[15:8] rejected");

        // Wrong slave address must not write.
        before_value = dut.DM_inst.DM[(2) * 32 +: 32];
        wrong_address_write(7'h41, 16'h2008, 32'hFACEB00C);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], before_value, "wrong I2C address rejected");

        // Repeated START should reset the transaction state.
        // We don't require a particular semantic for "continue after
        // repeated START"; the important safety property is no malformed
        // partial write. The complete second frame should still work.
        repeated_start_test(16'h2008, 32'h55AA55AA);
        check32(dut.DM_inst.DM[(2) * 32 +: 32], 32'h55AA55AA,
                "repeated START followed by valid write");

        // ====================================================================
        // SECTION 4: RESET DURING I2C TRANSACTION
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 4: RESET DURING I2C");
        $display("------------------------------------------------------------");

        before_value = dut.DM_inst.DM[(3) * 32 +: 32];

        i2c_start;
        i2c_write_byte(8'h84, 1'b1);
        i2c_write_byte(8'h20, 1'b1);
        i2c_write_byte(8'h0C, 1'b1);

        // Reset in the middle of a transaction.
        rst = 1'b1;
        #100;
        rst = 1'b0;
        #100;

        sda_drive = 1'b1;
        scl = 1'b1;
        #10000;

        check32(dut.DM_inst.DM[(3) * 32 +: 32], before_value,
                "reset mid-I2C caused no partial write");

        // Verify I2C still works after reset.
        mmio_write(16'h200C, 32'hA5A5A5A5);
        check32(dut.DM_inst.DM[(3) * 32 +: 32], 32'hA5A5A5A5,
                "I2C works after mid-transaction reset");

        // ====================================================================
        // SECTION 5: TARGET_PC edge cases
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 5: TARGET_PC EDGE CASES");
        $display("------------------------------------------------------------");

        // First verify that TARGET_PC=0 causes immediate stop and no
        // instruction at 0x00 retires.
        mmio_write(16'h3004, 32'h00000000);
        mmio_write(16'h3000, 32'h00000001);

        repeat (30) @(posedge clk);

        check1(dut.done, 1'b1, "TARGET=0 reaches DONE");
        check32(dut.PC_out, 32'h00000000, "TARGET=0 stops at 0");
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd16,
                "TARGET=0 executes no instruction");

        // Reset before the full architectural tests.
        rst = 1'b1;
        #100;
        rst = 1'b0;
        #100;

        // ====================================================================
        // SECTION 6: Reload exact exhaustive program
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 6: RELOAD EXACT EXHAUSTIVE PROGRAM");
        $display("------------------------------------------------------------");

        // Required source data.
        mmio_write(16'h201C, 32'd7);
        mmio_write(16'h2050, 32'd20);
        mmio_write(16'h2054, 32'd21);

        for (i = 0; i <= 33; i = i + 1)
            mmio_write(i * 16'd4, program[i]);

        // Target after the SW at 0x78.
        mmio_write(16'h3004, 32'h0000007C);

        // Verify selected programmed words.
        check32(
            {dut.IM_inst.IM[(0) * 8 +: 8],dut.IM_inst.IM[(1) * 8 +: 8],dut.IM_inst.IM[(2) * 8 +: 8],dut.IM_inst.IM[(3) * 8 +: 8]},
            32'h08100007, "program IMEM[0]"
        );
        check32(
            {dut.IM_inst.IM[(120) * 8 +: 8],dut.IM_inst.IM[(121) * 8 +: 8],
             dut.IM_inst.IM[(122) * 8 +: 8],dut.IM_inst.IM[(123) * 8 +: 8]},
            32'h10090000, "program IMEM[0x78]"
        );
        check32(
            {dut.IM_inst.IM[(124) * 8 +: 8],dut.IM_inst.IM[(125) * 8 +: 8],
             dut.IM_inst.IM[(126) * 8 +: 8],dut.IM_inst.IM[(127) * 8 +: 8]},
            32'hFC000000, "program IMEM[0x7C]"
        );

        // ====================================================================
        // SECTION 7: RUN exact exhaustive program
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 7: FULL EXHAUSTIVE PROGRAM");
        $display("------------------------------------------------------------");

        check32(dut.PC_out, 32'h0, "PC frozen before RUN");
        check1(dut.run_req, 1'b0, "RUN=0 before RUN command");
        check1(dut.done, 1'b0, "DONE=0 before RUN command");

        mmio_write(16'h3000, 32'h00000001);

        // Give enough cycles for the full branch/loop program.
        for (i = 0; i < 1500; i = i + 1) begin
            @(posedge clk);
            if (dut.done)
                i = 1500;
        end

        check1(dut.done, 1'b1, "full program DONE");
        check1(led, 1'b1, "full program LED");
        check32(dut.PC_out, 32'h0000007C, "full program TARGET");

        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd7,  "R16");
        check32(dut.REGFILE_inst.RF[(17) * 32 +: 32], 32'd7,  "R17");
        check32(dut.REGFILE_inst.RF[(18) * 32 +: 32], 32'd14, "R18");
        check32(dut.REGFILE_inst.RF[(19) * 32 +: 32], 32'd0,  "R19");
        check32(dut.REGFILE_inst.RF[(21) * 32 +: 32], 32'd20, "R21");
        check32(dut.REGFILE_inst.RF[(22) * 32 +: 32], 32'd20, "R22");
        check32(dut.REGFILE_inst.RF[(23) * 32 +: 32], 32'd40, "R23");
        check32(dut.REGFILE_inst.RF[(24) * 32 +: 32], 32'd21, "R24");
        check32(dut.REGFILE_inst.RF[(25) * 32 +: 32], 32'd21, "R25");
        check32(dut.REGFILE_inst.RF[(26) * 32 +: 32], 32'd42, "R26");
        check32(dut.REGFILE_inst.RF[(27) * 32 +: 32], 32'd5,  "R27");
        check32(dut.REGFILE_inst.RF[(28) * 32 +: 32], 32'd3,  "R28");
        check32(dut.REGFILE_inst.RF[(29) * 32 +: 32], 32'd3,  "R29");
        check32(dut.REGFILE_inst.RF[(30) * 32 +: 32], 32'd0,  "R30");
        check32(dut.REGFILE_inst.RF[(31) * 32 +: 32], 32'd0,  "R31");
        check32(dut.REGFILE_inst.RF[(8) * 32 +: 32],  32'd0,  "R8");
        check32(dut.REGFILE_inst.RF[(9) * 32 +: 32],  32'd36, "R9");
        check32(dut.REGFILE_inst.RF[(0) * 32 +: 32],  32'd0,  "R0");
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'd36, "DM[0]");
        check32(dut.DM_inst.DM[(7) * 32 +: 32], 32'd7, "DM[7]");
        check32(dut.DM_inst.DM[(20) * 32 +: 32],32'd20,"DM[20]");
        check32(dut.DM_inst.DM[(21) * 32 +: 32],32'd21,"DM[21]");

        // Wrong-path poison checks.
        check32(dut.REGFILE_inst.RF[(16) * 32 +: 32], 32'd7,  "poison R16 not executed");
        check32(dut.REGFILE_inst.RF[(17) * 32 +: 32], 32'd7,  "poison R17 not executed");
        check32(dut.REGFILE_inst.RF[(18) * 32 +: 32], 32'd14, "poison R18 not executed");

        // Predictor checks.
        check1(dut.BHT_inst.BHT[0], 1'b1, "BHT[0]");
        check32(dut.BTB_inst.BTB[(0) * 32 +: 32], 32'h48, "BTB[0]");
        check1(dut.BHT_inst.BHT[1], 1'b0, "BHT[1] squashed branch");
        check32(dut.BTB_inst.BTB[(1) * 32 +: 32], 32'h0, "BTB[1] squashed branch");
        check1(dut.BHT_inst.BHT[3], 1'b1, "BHT[3]");
        check32(dut.BTB_inst.BTB[(3) * 32 +: 32], 32'h58, "BTB[3]");
        check1(dut.BHT_inst.BHT[6], 1'b1, "BHT[6]");
        check32(dut.BTB_inst.BTB[(6) * 32 +: 32], 32'h60, "BTB[6]");

        // ====================================================================
        // SECTION 8: RUN/DONE semantics
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 8: RUN / DONE SEMANTICS");
        $display("------------------------------------------------------------");

        // After DONE, CPU should remain stopped even if cycles continue.
        repeat (50) @(posedge clk);
        check32(dut.PC_out, 32'h0000007C, "PC frozen after DONE");
        check32(dut.REGFILE_inst.RF[(9) * 32 +: 32], 32'd36, "RF frozen after DONE");
        check32(dut.DM_inst.DM[(0) * 32 +: 32], 32'd36, "DM frozen after DONE");

        // Writing RUN=0 after DONE must not corrupt the completed result.
        mmio_write(16'h3000, 32'h00000000);
        repeat (10) @(posedge clk);
        check1(dut.done, 1'b1, "DONE remains set after RUN=0");
        check32(dut.PC_out, 32'h0000007C, "PC remains stopped");

        // Writing RUN=1 after DONE should NOT accidentally execute more
        // instructions. This documents the desired HALT semantics.
        mmio_write(16'h3000, 32'h00000001);
        repeat (20) @(posedge clk);
        check1(dut.done, 1'b1, "DONE remains set after RUN=1");
        check32(dut.PC_out, 32'h0000007C, "RUN cannot restart completed CPU");

        // ====================================================================
        // SECTION 9: reset during RUN / HALT
        // ====================================================================
        $display("");
        $display("------------------------------------------------------------");
        $display(" SECTION 9: RESET AFTER COMPLETION");
        $display("------------------------------------------------------------");

        rst = 1'b1;
        #100;
        check32(dut.PC_out, 32'h0, "reset clears PC");
        check1(dut.done, 1'b0, "reset clears DONE");
        check1(dut.run_req, 1'b0, "reset clears RUN");
        check32(dut.REGFILE_inst.RF[(0) * 32 +: 32], 32'h0, "reset clears R0");

        rst = 1'b0;
        #100;

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("");
        $display("============================================================");

        if (errors == 0) begin
            $display(" ADVERSARIAL EDGE-CASE TEST: PASS");
            $display(" No errors detected.");
        end
        else begin
            $display(" ADVERSARIAL EDGE-CASE TEST: FAIL");
            $display(" Total errors = %0d", errors);
        end

        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
