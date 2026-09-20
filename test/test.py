# SPDX-License-Identifier: Apache-2.0
"""
Cocotb test for the I2C-programmable MIPS Tiny Tapeout project.

Bit-bangs the same I2C write/read protocol used by test/tb_top.v (the
standalone Icarus testbench), loads a tiny 4-instruction program, runs it,
and checks that DONE/led asserts and that the computed result lands in
data memory.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

SLAVE_ADDR = 0x42


async def i2c_delay(dut):
    await Timer(50, units="ns")


def sda_bus_value(dut):
    """Combine the DUT's open-drain output with the pull-up default."""
    if int(dut.uio_oe.value) & 0x1:
        return int(dut.uio_out.value) & 0x1
    return 1  # pulled up when nobody drives it


async def i2c_start(dut):
    dut.uio_in.value = int(dut.uio_in.value) | 0x1
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) | 0x1  # SCL high
    await i2c_delay(dut)
    dut.uio_in.value = int(dut.uio_in.value) & ~0x1  # SDA falls while SCL high
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x1  # SCL low
    await i2c_delay(dut)


async def i2c_stop(dut):
    dut.uio_in.value = int(dut.uio_in.value) & ~0x1
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) | 0x1
    await i2c_delay(dut)
    dut.uio_in.value = int(dut.uio_in.value) | 0x1  # SDA rises while SCL high
    await i2c_delay(dut)


async def i2c_write_byte(dut, data):
    for i in range(7, -1, -1):
        bit = (data >> i) & 1
        if bit:
            dut.uio_in.value = int(dut.uio_in.value) | 0x1
        else:
            dut.uio_in.value = int(dut.uio_in.value) & ~0x1
        await i2c_delay(dut)
        dut.ui_in.value = int(dut.ui_in.value) | 0x1
        await i2c_delay(dut)
        dut.ui_in.value = int(dut.ui_in.value) & ~0x1
        await i2c_delay(dut)
    # release SDA for the slave's ACK
    dut.uio_in.value = int(dut.uio_in.value) | 0x1
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) | 0x1
    await i2c_delay(dut)
    ack = (sda_bus_value(dut) == 0)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x1
    await i2c_delay(dut)
    return ack


async def i2c_read_byte(dut, send_ack):
    dut.uio_in.value = int(dut.uio_in.value) | 0x1  # release SDA
    data = 0
    for _ in range(8):
        dut.ui_in.value = int(dut.ui_in.value) | 0x1
        await i2c_delay(dut)
        data = (data << 1) | sda_bus_value(dut)
        dut.ui_in.value = int(dut.ui_in.value) & ~0x1
        await i2c_delay(dut)
    if send_ack:
        dut.uio_in.value = int(dut.uio_in.value) & ~0x1
    else:
        dut.uio_in.value = int(dut.uio_in.value) | 0x1
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) | 0x1
    await i2c_delay(dut)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x1
    await i2c_delay(dut)
    dut.uio_in.value = int(dut.uio_in.value) | 0x1
    return data & 0xFF


async def mmio_write(dut, addr, data):
    await i2c_start(dut)
    await i2c_write_byte(dut, (SLAVE_ADDR << 1) | 0)
    await i2c_write_byte(dut, (addr >> 8) & 0xFF)
    await i2c_write_byte(dut, addr & 0xFF)
    await i2c_write_byte(dut, (data >> 24) & 0xFF)
    await i2c_write_byte(dut, (data >> 16) & 0xFF)
    await i2c_write_byte(dut, (data >> 8) & 0xFF)
    await i2c_write_byte(dut, data & 0xFF)
    await i2c_stop(dut)


async def mmio_read(dut, addr):
    await i2c_start(dut)
    await i2c_write_byte(dut, (SLAVE_ADDR << 1) | 0)
    await i2c_write_byte(dut, (addr >> 8) & 0xFF)
    await i2c_write_byte(dut, addr & 0xFF)
    await i2c_start(dut)  # repeated START
    await i2c_write_byte(dut, (SLAVE_ADDR << 1) | 1)
    b0 = await i2c_read_byte(dut, True)
    b1 = await i2c_read_byte(dut, True)
    b2 = await i2c_read_byte(dut, True)
    b3 = await i2c_read_byte(dut, False)  # NACK final byte
    await i2c_stop(dut)
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3


@cocotb.test()
async def test_load_run_halt(dut):
    clock = Clock(dut.clk, 10, units="ns")  # 100 MHz system clock
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 1  # idle SDA = pulled up
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # LOAD: addi $1,$0,5 ; addi $2,$0,7 ; add $3,$1,$2 ; sw $3,0($0)
    await mmio_write(dut, 0x0000, 0x08010005)
    await mmio_write(dut, 0x0004, 0x08020007)
    await mmio_write(dut, 0x0008, 0x00221800)
    await mmio_write(dut, 0x000C, 0x10030000)
    await mmio_write(dut, 0x3004, 0x00000010)  # TARGET_PC

    readback = await mmio_read(dut, 0x0008)
    assert readback == 0x00221800, f"IMEM readback mismatch: {readback:#010x}"

    # RUN
    await mmio_write(dut, 0x3000, 0x00000001)

    # wait for DONE/led with a timeout
    for _ in range(2000):
        if int(dut.uo_out.value) & 0x1:
            break
        await ClockCycles(dut.clk, 1)
    assert int(dut.uo_out.value) & 0x1, "DONE/led never asserted"

    await ClockCycles(dut.clk, 10)
    result = await mmio_read(dut, 0x2000)
    assert result == 12, f"DMEM[0] = {result}, expected 12 (5+7)"
