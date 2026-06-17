@echo off
title USRP B210 Loopback Test (15 Msps)
echo =======================================================
echo  USRP B210 / Stratix-V Loopback Test
echo =======================================================
echo.
echo [Info] Stratix-Vのクロック(240MHz/120MHz)に合わせ、
echo        RFサンプリングレートを 15 Msps に設定して実行します。
echo.

REM benchmark_rate.exe を実行
REM ※すでにbenchmark_rate.cpp側でデフォルト値を15e6に書き換えていますが、
REM   明示的にパラメータを渡すことでより確実に動作させます。
benchmark_rate.exe --tx_rate 15e6 --rx_rate 15e6

echo.
echo =======================================================
echo  テストが終了しました。
echo =======================================================
pause
