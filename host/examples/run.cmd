@echo off
chcp 65001 >nul
title USRP B210 / Stratix-V Loopback Test

echo =======================================================
echo  USRP B210 / Stratix-V WLAN HDL Loopback Test
echo =======================================================
echo.
echo  Master Clock Rate : 30 MHz
echo  TX/RX Sample Rate : 15 Msps
echo  RF Frequency      : 2400 MHz
echo.
echo  MCR=30MHz -> radio_clk=30MHz -> debug_clk[1]=30MHz
echo  -> I/Q serialization at 30MHz = 15 Msps pairs
echo  -> Matches Stratix-V 240MHz/16 = 15 Msps
echo.

REM IMPORTANT: master_clock_rate=30e6 is required!
REM This sets AD9361 codec_data_clk = 30MHz, so radio_clk = 30MHz (SISO).
REM The I/Q serialization on debug_clk[1] then produces exactly 15 Msps,
REM matching the Stratix-V's transmitter rate.

benchmark_rate.exe --tx_rate 15e6 --rx_rate 15e6 --args "master_clock_rate=30e6"

echo.
echo =======================================================
echo  Test completed.
echo =======================================================
pause
