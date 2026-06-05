`timescale 100fs/1fs

module b210_tb ();
  
  //
  // Xilinx Mandatory Simulation Primitive for global signals.
  //
  wire GSR, GTS;
  glbl glbl ();

  //
  // Test bench
  //
  reg  btn_reset = 1'b0;
  reg  btn_tx_start = 1'b0;
  reg  btn_rx_start = 1'b0;

  reg tx_clock = 1'b0;
  reg rx_clock = 1'b0;
  always #(10000000/240/2) tx_clock = ~tx_clock; // 240 MHz
  always #(10000000/120/2) rx_clock = ~rx_clock; // 120 MHz

  wire        tx_bits_enable;
  wire [ 7:0] tx_bits_in = 8'b11001100;
  wire        tx_data_clock;
  wire        tx_data_frame;
  wire        tx_data_valid;
  wire [11:0] tx_data;

  wire        rx_data_clock;
  wire        rx_data_frame;
  wire        rx_data_valid;
  wire [11:0] rx_data;
  wire        rx_bits_valid;
  wire [ 7:0] rx_bits_out;
  wire [ 7:0] rx_bits_expected = tx_bits_in;
  wire [19:0] rx_bytes_count_valid;
  wire [19:0] rx_bytes_count_invalid;
  wire [ 2:0] rx_mcs;
  wire [ 1:0] rx_frame_format;
  wire        rx_parity_status;
  wire        rx_crc_status;

  WLANHDLLoopback loopback (
    .btn_reset(btn_reset), 
    .btn_tx_start(btn_tx_start),
    .btn_rx_start(btn_rx_start),
    .tx_clock(tx_clock), 
    .tx_bits_enable(tx_bits_enable),
    .tx_bits_in(tx_bits_in),
    .tx_data_clock(tx_data_clock), 
    .tx_data_frame(tx_data_frame), 
    .tx_data_valid(tx_data_valid), 
    .tx_data(tx_data), 
    .rx_clock(rx_clock), 
    .rx_data_clock(rx_data_clock), 
    .rx_data_frame(rx_data_frame),
    .rx_data_valid(rx_data_valid),
    .rx_data(rx_data),
    .rx_bits_valid(rx_bits_valid),
    .rx_bits_out(rx_bits_out),
    .rx_bytes_expected(rx_bits_expected),
    .rx_bytes_count_valid(rx_bytes_count_valid),
    .rx_bytes_count_invalid(rx_bytes_count_invalid),
    .rx_mcs(rx_mcs),
    .rx_frame_format(rx_frame_format),
    .rx_parity_status(rx_parity_status),
    .rx_crc_status(rx_crc_status)
  );

  reg         codec_data_clk_p = 1'b0;
  always #(10000000/20/2) codec_data_clk_p = ~codec_data_clk_p; // 20 MHz
  wire        codec_fb_clk_p;
  wire [11:0] rx_codec_d, tx_codec_d;
  assign rx_codec_d = tx_codec_d;
  wire        rx_frame_p, tx_frame_p;
  assign rx_frame_p = tx_frame_p;
  reg         codec_main_clk_p = 1'b0;
  reg         codec_main_clk_n = 1'b1;
  always #(10000000/40/2) codec_main_clk_p = ~codec_main_clk_p; // 40 MHz
  always #(10000000/40/2) codec_main_clk_n = ~codec_main_clk_n; // 40 MHz
  wire [ 1:0] debug_clk;
  wire [31:0] debug;

  assign debug_clk[0] = tx_data_clock;
  assign debug[31]    = tx_data_frame;
  assign debug[30]    = tx_data_valid;
  assign debug[29]    = tx_data[11];
  assign debug[28]    = tx_data[10];
  assign debug[27]    = tx_data[ 9];
  assign debug[26]    = tx_data[ 8];
  assign debug[25]    = tx_data[ 7];
  assign debug[24]    = tx_data[ 6];
  assign debug[23]    = tx_data[ 5];
  assign debug[22]    = tx_data[ 4];
  assign debug[21]    = tx_data[ 3];
  assign debug[20]    = tx_data[ 2];
  assign debug[19]    = tx_data[ 1];
  assign debug[18]    = tx_data[ 0];
  assign debug[17]    = btn_reset;
  assign debug[16]    = 1'b0;

  assign rx_data_clock = debug_clk[1];
  assign rx_data_frame = debug[15];
  assign rx_data_valid = debug[14];
  assign rx_data[11]   = debug[13];
  assign rx_data[10]   = debug[12];
  assign rx_data[ 9]   = debug[11];
  assign rx_data[ 8]   = debug[10];
  assign rx_data[ 7]   = debug[ 9];
  assign rx_data[ 6]   = debug[ 8];
  assign rx_data[ 5]   = debug[ 7];
  assign rx_data[ 4]   = debug[ 6];
  assign rx_data[ 3]   = debug[ 5];
  assign rx_data[ 2]   = debug[ 4];
  assign rx_data[ 1]   = debug[ 3];
  assign rx_data[ 0]   = debug[ 2];
  assign debug[ 1]    = 1'b0;
  assign debug[ 0]    = 1'b0;

  b200 b200_0 (
    .cat_ce(), .cat_miso(1'bz), .cat_mosi(), .cat_sclk(),
    .fx3_ce(1'bz), .fx3_miso(), .fx3_mosi(1'bz), .fx3_sclk(1'bz),
    .pll_ce(), .pll_mosi(), .pll_sclk(),
    .FPGA_RXD0(), .FPGA_TXD0(),
    .codec_enable(), .codec_en_agc(), .codec_reset(), .codec_sync(), .codec_txrx(), .codec_ctrl_in(), .codec_ctrl_out(8'hzz),
    .codec_data_clk_p(codec_data_clk_p), .codec_fb_clk_p(codec_fb_clk_p), 
    .rx_codec_d(rx_codec_d), .tx_codec_d(tx_codec_d), .rx_frame_p(rx_frame_p), .tx_frame_p(tx_frame_p),
    .cat_clkout_fpga(1'bz),
    .codec_main_clk_p(codec_main_clk_p), .codec_main_clk_n(codec_main_clk_n),
    .debug(debug), .debug_clk(debug_clk),
    .IFCLK(), .FX3_EXTINT(1'bz), .GPIF_CTL0(), .GPIF_CTL1(), .GPIF_CTL2(), .GPIF_CTL3(), .GPIF_CTL7(), 
    .GPIF_CTL4(1'bz), .GPIF_CTL5(1'bz), .GPIF_CTL6(1'bz), .GPIF_CTL8(1'bz), .GPIF_CTL11(), .GPIF_CTL12(), .GPIF_D(), .GPIF_CTL9(btn_reset),
    .gps_lock(1'bz), .gps_rxd(), .gps_txd(1'bz), .gps_txd_nmea(1'bz),
    .LED_RX1(), .LED_RX2(), .LED_TXRX1_RX(), .LED_TXRX1_TX(), .LED_TXRX2_RX(), .LED_TXRX2_TX(),
    .fp_gpio(),
    .ref_sel(), .pll_lock(1'b1), .FPGA_CFG_CS(1'bz), .AUX_PWR_ON(1'bz),
    .PPS_IN_EXT(1'bz), .PPS_IN_INT(1'bz), 
    .SFDX1_RX(), .SFDX1_TX(), .SFDX2_RX(), .SFDX2_TX(),
    .SRX1_RX(), .SRX1_TX(), .SRX2_RX(), .SRX2_TX(),
    .tx_bandsel_a(), .tx_bandsel_b(), .tx_enable1(), .tx_enable2(), 
    .rx_bandsel_a(), .rx_bandsel_b(), .rx_bandsel_c()
  );

  initial begin
    // ---- VCD出力設定を追加 ----
    $dumpfile("b210_tb.vcd"); // 保存されるファイル名
    $dumpvars(0, b210_tb);            // b210_tb 以下のすべての階層 of signals
    $dumpvars(0, b210_tb.b200_0);     // b200_0  以下のすべての階層 of signals
    $dumpvars(0, b210_tb.loopback);   // loopback 以下のすべての階層 of signals
    $dumpvars(0, glbl);               // グローバル信号をダンプ
    // --------------------------
    #(1000000) btn_reset <= 1; btn_tx_start <= 0; btn_rx_start <= 0;
    #(1000000) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    
    // Wait for the FPGA internal clocks to be fully ready (takes ~655 us)
    @(posedge b200_0.clocks_ready);
    
    #(1000000) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 1;
    #(1000000) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    #(1000000) btn_reset <= 0; btn_tx_start <= 1; btn_rx_start <= 0;
    #(1000000) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    
    // Run for another 400 us (covers the packet transmission)
    #(2000000000)
    #(2000000000)
    #(2000000000)
    #(2000000000)
    #(2000000000) $finish;
  end

endmodule
