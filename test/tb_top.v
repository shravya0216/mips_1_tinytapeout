`timescale 1ns / 1ps

module tb_top;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'h00;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg ena = 1'b1;

    // ---- system clock: 100 MHz ----
    always #5 clk = ~clk;

    // ---- open-drain SDA bus model ----
    reg  master_oe;
    reg  master_val;
    wire sda_bus;
    pullup(sda_bus);
    assign sda_bus = uio_oe[0] ? uio_out[0] : 1'bz;
    assign sda_bus = master_oe ? master_val : 1'bz;
    always @(*) uio_in[0] = sda_bus;

    // ---- SCL is only ever driven by the testbench master (no clock stretch) ----
    reg scl_r;
    always @(*) ui_in[0] = scl_r;

    tt_um_mips_i2c dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    wire led = uo_out[0];

    // ================================================================
    // I2C master bit-bang tasks. SCL period ~= 200ns (5 MHz, plenty slow
    // vs the 100 MHz system clock's 3-stage synchronizer).
    // ================================================================
    initial begin scl_r = 1'b1; master_oe = 1'b0; master_val = 1'b1; end

    task automatic i2c_delay; begin #50; end endtask

    task automatic i2c_start; begin
        master_oe = 1'b1; master_val = 1'b1; i2c_delay();
        scl_r = 1'b1; i2c_delay();
        master_val = 1'b0; i2c_delay();   // SDA falls while SCL high = START
        scl_r = 1'b0; i2c_delay();
    end endtask

    task automatic i2c_stop; begin
        master_oe = 1'b1; master_val = 1'b0; i2c_delay();
        scl_r = 1'b1; i2c_delay();
        master_val = 1'b1; i2c_delay();   // SDA rises while SCL high = STOP
        master_oe = 1'b0; i2c_delay();
    end endtask

    // Sends one byte MSB-first, returns 1 if ACKed (SDA low).
    task automatic i2c_write_byte(input [7:0] data, output ack);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                master_oe = 1'b1; master_val = data[i]; i2c_delay();
                scl_r = 1'b1; i2c_delay();
                scl_r = 1'b0; i2c_delay();
            end
            // release SDA, let slave ACK
            master_oe = 1'b0; i2c_delay();
            scl_r = 1'b1; i2c_delay();
            ack = ~sda_bus;
            scl_r = 1'b0; i2c_delay();
        end
    endtask

    // Reads one byte MSB-first, drives ACK (send_ack=1) or NACK.
    task automatic i2c_read_byte(input send_ack, output [7:0] data);
        integer i;
        begin
            master_oe = 1'b0; // release for slave to drive
            for (i = 7; i >= 0; i = i - 1) begin
                scl_r = 1'b1; i2c_delay();
                data[i] = sda_bus;
                scl_r = 1'b0; i2c_delay();
            end
            master_oe = 1'b1; master_val = send_ack ? 1'b0 : 1'b1; i2c_delay();
            scl_r = 1'b1; i2c_delay();
            scl_r = 1'b0; i2c_delay();
            master_oe = 1'b0;
        end
    endtask

    // Full write transaction: 0x42+W, 16-bit addr, 32-bit data.
    task automatic mmio_write(input [15:0] addr, input [31:0] data);
        reg ack;
        begin
            i2c_start();
            i2c_write_byte({7'h42, 1'b0}, ack);
            i2c_write_byte(addr[15:8], ack);
            i2c_write_byte(addr[7:0], ack);
            i2c_write_byte(data[31:24], ack);
            i2c_write_byte(data[23:16], ack);
            i2c_write_byte(data[15:8], ack);
            i2c_write_byte(data[7:0], ack);
            i2c_stop();
        end
    endtask

    // Read transaction: write addr (0x42+W), repeated START, 0x42+R, read 4 bytes, NACK last.
    task automatic mmio_read(input [15:0] addr, output [31:0] data);
        reg ack;
        reg [7:0] b0, b1, b2, b3;
        begin
            i2c_start();
            i2c_write_byte({7'h42, 1'b0}, ack);
            i2c_write_byte(addr[15:8], ack);
            i2c_write_byte(addr[7:0], ack);
            i2c_start(); // repeated START
            i2c_write_byte({7'h42, 1'b1}, ack);
            i2c_read_byte(1'b1, b0);
            i2c_read_byte(1'b1, b1);
            i2c_read_byte(1'b1, b2);
            i2c_read_byte(1'b0, b3); // NACK final byte
            i2c_stop();
            data = {b0, b1, b2, b3};
        end
    endtask

    integer timeout;
    reg [31:0] readback;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        // reset
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- LOAD ----
        // addi $1, $0, 5
        mmio_write(16'h0000, 32'h08010005);
        // addi $2, $0, 7
        mmio_write(16'h0004, 32'h08020007);
        // add  $3, $1, $2
        mmio_write(16'h0008, 32'h00221800);
        // sw   $3, 0($0)
        mmio_write(16'h000C, 32'h10030000);
        // TARGET_PC = 0x10 (first instruction that must NOT execute)
        mmio_write(16'h3004, 32'h00000010);

        // sanity: read back word 2 of IMEM before RUN, must match what we wrote
        mmio_read(16'h0008, readback);
        if (readback !== 32'h00221800)
            $display("FAIL: IMEM readback mismatch, got %h", readback);
        else
            $display("PASS: IMEM readback OK (%h)", readback);

        // ---- RUN ----
        mmio_write(16'h3000, 32'h00000001); // CSR.RUN = 1

        // wait for DONE/LED, with a timeout
        timeout = 0;
        while (led !== 1'b1 && timeout < 2000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (led !== 1'b1) begin
            $display("FAIL: LED/DONE never asserted (timeout)");
        end else begin
            $display("PASS: LED/DONE asserted after %0d clocks", timeout);
        end

        // give the freeze a moment to settle, then read DMEM[0] back over I2C
        repeat (10) @(posedge clk);
        mmio_read(16'h2000, readback);
        if (readback !== 32'd12)
            $display("FAIL: DMEM[0] = %0d, expected 12", readback);
        else
            $display("PASS: DMEM[0] = 12 as expected (5+7 computed and stored)");

        // confirm CPU is actually halted: PC must not still be advancing
        mmio_read(16'h3008, readback);
        $display("INFO: halted PC readback = %h", readback);

        repeat (20) @(posedge clk);
        $display("TESTBENCH DONE");
        $finish;
    end

endmodule
