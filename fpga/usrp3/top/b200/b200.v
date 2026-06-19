//
// Copyright 2013 Ettus Research LLC
// Copyright 2017 Ettus Research, a National Instruments Company
//
// SPDX-License-Identifier: LGPL-3.0-or-later
//

/***********************************************************
 * B200 Module Declaration
 * Modified for Stratix-V WLAN HDL Loopback
 *
 * Architecture:
 *   Stratix-V <==> debug bus <==> [b200.v custom logic] <==> b200_io <==> AD9361
 *   b200_core is retained for SPI/register control only (data path disconnected)
 *
 * TX: Stratix-V debug[31:17]/debug_clk[0] -> bus_clk sync -> CDC -> b200_io -> AD9361 DAC
 * RX: AD9361 ADC -> b200_io -> radio_clk serialize -> debug[15:0]/debug_clk[1] -> Stratix-V
 **********************************************************/
module b200 
  (
    // SPI Interfaces
    output        cat_ce,
    input         cat_miso,
    output        cat_mosi,
    output        cat_sclk,

    input         fx3_ce,
    output        fx3_miso,
    input         fx3_mosi,
    input         fx3_sclk,

    output        pll_ce,
    output        pll_mosi,
    output        pll_sclk,

    // UART
    // By default these provide an FX3 UART console output. Under compile time control they can alternatively
    // provide 2 (1.8V) GPIO pins which are logically bits [9:8] of the fp_gpio bus.
    // Used as a UART RXD is an input and TXD an output electrically.
    inout         FPGA_RXD0, // These pins goto 3 pin 0.1" header J400 on B2x0 and
    inout         FPGA_TXD0, // carry FX3 UART.

    // Catalina Controls
    output        codec_enable,
    output        codec_en_agc,
    output        codec_reset,
    output        codec_sync,
    output        codec_txrx,
    output [ 3:0] codec_ctrl_in,  // These should be outputs
    input  [ 7:0] codec_ctrl_out, // MUST BE INPUT

    // Catalina Data
    input         codec_data_clk_p, // Clock from CAT (RX)
    output        codec_fb_clk_p,   // Clock to CAT (TX)
    input  [11:0] rx_codec_d,
    output [11:0] tx_codec_d,
    input         rx_frame_p,
    output        tx_frame_p,

    input         cat_clkout_fpga,

    // always on 40MHz clock
    input         codec_main_clk_p,
    input         codec_main_clk_n,

    // Debug Bus
    inout  [31:0] debug,
    inout  [ 1:0] debug_clk,

    // GPIF, FX3 Slave FIFO
    output        IFCLK,      // pclk
    input         FX3_EXTINT, 
    output        GPIF_CTL0,  // n_slcs
    output        GPIF_CTL1,  // n_slwr
    output        GPIF_CTL2,  // n_sloe
    output        GPIF_CTL3,  // n_slrd
    output        GPIF_CTL7,  // n_pktend
    input         GPIF_CTL4,  // slfifo_flags[0]
    input         GPIF_CTL5,  // slfifo_flags[1]
    input         GPIF_CTL6,  // Serial settings bus from FX3. SDA
    input         GPIF_CTL8,  // Serial settings bus from FX3. SCL
    output        GPIF_CTL11, // slfifo_addr[1]
    output        GPIF_CTL12, // slfifo_addr[0]
    inout  [31:0] GPIF_D,
    input         GPIF_CTL9,  // global_reset

    // GPS
    input         gps_lock,
    output        gps_rxd,
    input         gps_txd,      // FPGA has pullup for unpopulated GPS
    input         gps_txd_nmea, // FPGA has pullup for unpopulated GPS

    // LEDS
    output        LED_RX1,
    output        LED_RX2,
    output        LED_TXRX1_RX,
    output        LED_TXRX1_TX,
    output        LED_TXRX2_RX,
    output        LED_TXRX2_TX,

    // GPIO Header J504  - 10 pin 0.1" 3.3V.
    // Only present on Rev6 and later boards...these pins unused on Rev5 and earlier.
    // NOTE: These pins are allocated from complimentry pairs and could potentially be used
    // as differential style I/O.
    inout  [ 7:0] fp_gpio,

    // Misc Hardware Control
    output        ref_sel,
    input         pll_lock,
    input         FPGA_CFG_CS, // Driven by FX3 gpio.
    input         AUX_PWR_ON,  // Driven by FX3 gpio.

    // PPS
    input         PPS_IN_EXT,
    input         PPS_IN_INT,

    // RF Hardware Control
    output        SFDX1_RX,
    output        SFDX1_TX,
    output        SFDX2_RX,
    output        SFDX2_TX,
    output        SRX1_RX,
    output        SRX1_TX,
    output        SRX2_RX,
    output        SRX2_TX,
    output        tx_bandsel_a,
    output        tx_bandsel_b,
    output        tx_enable1,
    output        tx_enable2,
    output        rx_bandsel_a,
    output        rx_bandsel_b,
    output        rx_bandsel_c
  );

  wire reset_global = GPIF_CTL9;

  ///////////////////////////////////////////////////////////////////////
  // generate clocks from always on codec main clk
  ///////////////////////////////////////////////////////////////////////
  wire bus_clk, gpif_clk, radio_clk;
  wire locked;
  b200_clk_gen gen_clks (
    .CLK_IN1_40_P(codec_main_clk_p), 
    .CLK_IN1_40_N(codec_main_clk_n),
    .CLK_OUT1_40_int(), 
    .CLK_OUT2_100_gpif(gpif_clk), 
    .CLK_OUT3_100_bus(),
    .RESET(reset_global), 
    .LOCKED(locked)
  );

  // Bus Clock and GPIF Clock both same 100MHz clock.
  assign bus_clk = gpif_clk;

  //hold-off logic for clocks ready
  reg [15:0] clocks_ready_count;
  reg clocks_ready;
  always @(posedge bus_clk or posedge reset_global or negedge locked) begin
    if (reset_global | !locked) begin
      clocks_ready_count <= 16'b0;
      clocks_ready <= 1'b0;
    end else if (!clocks_ready) begin
      clocks_ready_count <= clocks_ready_count + 1'b1;
      clocks_ready <= (clocks_ready_count == 16'hffff);
    end
  end

  ///////////////////////////////////////////////////////////////////////
  // drive output clocks
  ///////////////////////////////////////////////////////////////////////
  S6CLK2PIN S6CLK2PIN_gpif (
    .I(gpif_clk), 
    .O(IFCLK)
  );

  ///////////////////////////////////////////////////////////////////////
  // Create sync reset signals
  ///////////////////////////////////////////////////////////////////////
  wire gpif_rst, bus_rst, radio_rst;
  reset_sync gpif_sync (
    .clk(gpif_clk), 
    .reset_in(!clocks_ready), 
    .reset_out(gpif_rst)
  );
  reset_sync bus_sync (
    .clk(bus_clk), 
    .reset_in(!clocks_ready), 
    .reset_out(bus_rst)
  );
  reset_sync radio_sync (
    .clk(radio_clk), 
    .reset_in(!clocks_ready), 
    .reset_out(radio_rst)
  );

  ///////////////////////////////////////////////////////////////////////
  //
  // Stratix-V Debug Bus Interface
  //
  // Pin mapping (directly wired to Mictor J502 via HSMC adapter):
  //   debug_clk[0]  : INPUT  - tx_data_clock from Stratix-V (30 MHz)
  //   debug_clk[1]  : OUTPUT - radio_clk to Stratix-V (= MCR)
  //   debug[31:17]  : INPUT  - tx_data_frame, tx_data_valid, tx_data[11:0], btn_reset
  //   debug[16]     : hi-Z   (unused)
  //   debug[15:0]   : OUTPUT - rx_data_frame, rx_data_valid, rx_data[11:0], 2x hi-Z
  //
  ///////////////////////////////////////////////////////////////////////

  // --- Input from Stratix-V ---
  wire        sv_tx_clock  = debug_clk[0];
  wire        sv_tx_frame  = debug[31];
  wire        sv_tx_valid  = debug[30];
  wire [11:0] sv_tx_data   = debug[29:18];
  wire        btn_reset    = debug[17];
  assign debug[16] = 1'bz;

  // --- Output to Stratix-V ---
  reg         sv_rx_frame;
  reg         sv_rx_valid;
  reg  [11:0] sv_rx_data;
  S6CLK2PIN S6CLK2PIN_debug_clk1 (
    .I(radio_clk), 
    .O(debug_clk[1])
  );
  assign debug[15]    = sv_rx_frame;
  assign debug[14]    = sv_rx_valid;
  assign debug[13]    = sv_rx_data[11];
  assign debug[12]    = sv_rx_data[10];
  assign debug[11]    = sv_rx_data[ 9];
  assign debug[10]    = sv_rx_data[ 8];
  assign debug[ 9]    = sv_rx_data[ 7];
  assign debug[ 8]    = sv_rx_data[ 6];
  assign debug[ 7]    = sv_rx_data[ 5];
  assign debug[ 6]    = sv_rx_data[ 4];
  assign debug[ 5]    = sv_rx_data[ 3];
  assign debug[ 4]    = sv_rx_data[ 2];
  assign debug[ 3]    = sv_rx_data[ 1];
  assign debug[ 2]    = sv_rx_data[ 0];
  assign debug[ 1]    = 1'bz;
  assign debug[ 0]    = 1'bz;

  ///////////////////////////////////////////////////////////////////////
  // TX path: Stratix-V -> AD9361
  //
  // Step 1: Deserialize I/Q from debug bus in bus_clk domain (100 MHz).
  //         bus_clk provides reliable oversampling of the 30 MHz tx_data_clock.
  // Step 2: CDC via toggle handshake into radio_clk domain.
  // Step 3: Feed to b200_io tx_i0/tx_q0 (sampled at siso_clk = radio_clk).
  ///////////////////////////////////////////////////////////////////////

  // Step 1: Deserialize in bus_clk (100 MHz)
  reg         sv_clk_r0, sv_clk_r1, sv_clk_r2;
  reg         sv_frame_r0, sv_frame_r1;
  reg         sv_valid_r0, sv_valid_r1, sv_valid_r2, sv_valid_bus;
  reg  [11:0] sv_data_r0, sv_data_r1;
  reg  [11:0] sv_re_r2, sv_im_r2, sv_re_bus, sv_im_bus;
  reg         sv_new_toggle = 1'b0;  // toggle flag for CDC

  always @(posedge bus_clk) begin
    if (bus_rst) begin
      sv_clk_r0      <= 1'b0;
      sv_clk_r1      <= 1'b0;
      sv_clk_r2      <= 1'b0;
      sv_frame_r0    <= 1'b0;
      sv_frame_r1    <= 1'b0;
      sv_valid_r0    <= 1'b0;
      sv_valid_r1    <= 1'b0;
      sv_valid_r2    <= 1'b0;
      sv_valid_bus   <= 1'b0;
      sv_data_r0     <= 12'h000;
      sv_data_r1     <= 12'h000;
      sv_re_r2       <= 12'h000;
      sv_im_r2       <= 12'h000;
      sv_re_bus      <= 12'h000;
      sv_im_bus      <= 12'h000;
      sv_new_toggle  <= 1'b0;
    end else begin
      // 2-stage synchronizer for async inputs
      sv_clk_r0   <= sv_tx_clock;
      sv_clk_r1   <= sv_clk_r0;
      sv_clk_r2   <= sv_clk_r1;
      sv_frame_r0 <= sv_tx_frame;
      sv_frame_r1 <= sv_frame_r0;
      sv_valid_r0 <= sv_tx_valid;
      sv_valid_r1 <= sv_valid_r0;
      sv_data_r0  <= sv_tx_data;
      sv_data_r1  <= sv_data_r0;

      // Detect rising edge of tx_data_clock (data is stable after rising edge)
      if (sv_clk_r2 == 1'b0 && sv_clk_r1 == 1'b1) begin
        sv_valid_r2 <= sv_valid_r1;
        if (sv_frame_r1 == 1'b1) begin
          // I phase: latch I, publish previous complete I/Q pair
          sv_re_r2      <= sv_data_r1;
          sv_re_bus     <= sv_re_r2;
          sv_im_bus     <= sv_im_r2;
          sv_valid_bus  <= sv_valid_r2;
          sv_new_toggle <= ~sv_new_toggle;  // signal new data for CDC
        end else begin
          // Q phase: latch Q
          sv_im_r2 <= sv_data_r1;
        end
      end
    end
  end

  // Step 2: CDC toggle handshake (bus_clk -> radio_clk)
  // The toggle ensures we only capture data when it is fully stable.
  reg  [2:0]  cdc_toggle_sync;
  reg  [11:0] tx_i0_cdc, tx_q0_cdc;
  reg         tx_valid_cdc;

  always @(posedge radio_clk) begin
    if (radio_rst) begin
      cdc_toggle_sync <= 3'b000;
      tx_i0_cdc       <= 12'h000;
      tx_q0_cdc       <= 12'h000;
      tx_valid_cdc    <= 1'b0;
    end else begin
      cdc_toggle_sync <= {cdc_toggle_sync[1:0], sv_new_toggle};
      if (cdc_toggle_sync[2] != cdc_toggle_sync[1]) begin
        // Toggle edge detected: bus_clk data has been stable for >= 2 radio_clk cycles
        tx_i0_cdc    <= sv_re_bus;
        tx_q0_cdc    <= sv_im_bus;
        tx_valid_cdc <= sv_valid_bus;
      end
    end
  end

  // Step 3: tx_i0_cdc / tx_q0_cdc feed directly into b200_io (see instantiation below).
  //         b200_io holds the last value as zero-order hold when MCR > sample rate.

  ///////////////////////////////////////////////////////////////////////
  // RX path: AD9361 -> Stratix-V
  //
  // b200_io outputs rx_i0/rx_q0 at radio_clk rate.
  // We serialize I and Q alternately (frame=1 for I, frame=0 for Q).
  // With MCR=30 MHz, this produces 15 Msps I/Q pairs at 30 MHz debug_clk[1].
  //
  // Envelope detection gates rx_valid to indicate presence of RF energy.
  ///////////////////////////////////////////////////////////////////////
  wire [11:0] rx_i0, rx_q0, rx_i1, rx_q1;  // from b200_io

  // Envelope detector: |I| + |Q| > threshold
  wire [11:0] abs_rx_i = rx_i0[11] ? (~rx_i0 + 1'b1) : rx_i0;
  wire [11:0] abs_rx_q = rx_q0[11] ? (~rx_q0 + 1'b1) : rx_q0;
  wire [12:0] rx_mag   = {1'b0, abs_rx_i} + {1'b0, abs_rx_q};
  wire        rx_above_threshold = (rx_mag > 13'd200);

  reg  [15:0] rx_hold_timer;
  reg  [11:0] rx_im_hold;

  always @(posedge radio_clk) begin
    if (radio_rst || btn_reset) begin
      sv_rx_frame  <= 1'b0;
      sv_rx_valid  <= 1'b0;
      sv_rx_data   <= 12'h000;
      rx_im_hold   <= 12'h000;
      rx_hold_timer <= 16'd0;
    end else begin
      // I/Q serialization: toggle frame each radio_clk cycle
      if (sv_rx_frame == 1'b0) begin
        // Frame=0 -> 1: capture new I/Q pair, output I
        rx_im_hold   <= rx_q0;
        sv_rx_data   <= rx_i0;
        sv_rx_frame  <= 1'b1;
      end else begin
        // Frame=1 -> 0: output Q from held value
        sv_rx_data   <= rx_im_hold;
        sv_rx_frame  <= 1'b0;
      end

      // Packet envelope logic
      if (rx_above_threshold) begin
        sv_rx_valid   <= 1'b1;
        rx_hold_timer <= 16'd100;
      end else if (rx_hold_timer > 16'd0) begin
        sv_rx_valid   <= 1'b1;
        rx_hold_timer <= rx_hold_timer - 1'b1;
      end else begin
        sv_rx_valid   <= 1'b0;
      end
    end
  end

  ///////////////////////////////////////////////////////////////////////
  // b200_io: AD9361 LVDS DDR interface
  //
  // Generates radio_clk from AD9361's codec_data_clk.
  // In SISO mode (mimo=0): radio_clk = codec_data_clk (= MCR).
  // TX: samples tx_i0/tx_q0 every siso_clk (= radio_clk) cycle.
  // RX: outputs rx_i0/rx_q0 every radio_clk cycle.
  ///////////////////////////////////////////////////////////////////////
  b200_io b200_io_i0 (
    .reset(!clocks_ready),
    .mimo(1'b0),
    
    // Baseband sample interface
    .radio_clk(radio_clk),
    .rx_i0(rx_i0), 
    .rx_q0(rx_q0), 
    .rx_i1(rx_i1), 
    .rx_q1(rx_q1),
    .tx_i0(tx_i0_cdc), 
    .tx_q0(tx_q0_cdc), 
    .tx_i1(12'h000), 
    .tx_q1(12'h000),
    
    .siso_clk_out(),
    .strobe(),

    // Catalina interface   
    .rx_clk(codec_data_clk_p), 
    .rx_frame(rx_frame_p),      
    .rx_data(rx_codec_d), 
    .tx_clk(codec_fb_clk_p), 
    .tx_frame(tx_frame_p), 
    .tx_data(tx_codec_d) 
  );
   
  ///////////////////////////////////////////////////////////////////////
  // SPI connections
  ///////////////////////////////////////////////////////////////////////
  wire mosi, miso, sclk;
  wire [7:0] sen;

  // AD9361 Slave
  assign cat_ce   = sen[0];
  assign cat_mosi = ~sen[0] & mosi;
  assign cat_sclk = ~sen[0] & sclk;
  assign miso     = cat_miso; // PLL does not have a miso

  // ADF4001 Slave
  assign pll_ce   = sen[1];
  assign pll_mosi = ~sen[1] & mosi;
  assign pll_sclk = ~sen[1] & sclk;

  // FX3 Master
  // The following signals are routed to the FX3 and were used by an obsolete
  // bit-banging SPI engine.
  // fx3_ce, fx3_sclk, fx3_mosi    <Unused>
  assign fx3_miso = 1'bZ; // Safe state because we cannot guarantee the
                          // direction of this pin in the FX3

  ///////////////////////////////////////////////////////////////////////
  // bus signals
  ///////////////////////////////////////////////////////////////////////
  wire [63:0] ctrl_tdata, resp_tdata, rx_tdata, tx_tdata;
  wire ctrl_tlast, resp_tlast, rx_tlast, tx_tlast;
  wire ctrl_tvalid, resp_tvalid, rx_tvalid, tx_tvalid;
  wire ctrl_tready, resp_tready, rx_tready, tx_tready;

  ///////////////////////////////////////////////////////////////////////
  // frontend assignments
  // Most B2x0's have frontends swapped (radio0 to FE2), but some hardware revisions do not.
  // The ATR pins are mapped from radio to frontend here based on the swap_atr_n bit.
  ///////////////////////////////////////////////////////////////////////
  wire swap_atr_n;
  wire [7:0] radio0_gpio, radio1_gpio;
  reg [7:0] fe0_gpio, fe1_gpio;
  always @(posedge radio_clk) begin // Registers in the IOB
    fe0_gpio <= swap_atr_n ? radio1_gpio : radio0_gpio;
    fe1_gpio <= swap_atr_n ? radio0_gpio : radio1_gpio;
  end
  assign {tx_enable1, SFDX1_RX, SFDX1_TX, SRX1_RX, SRX1_TX, LED_RX1, LED_TXRX1_RX, LED_TXRX1_TX} = fe0_gpio;
  assign {tx_enable2, SFDX2_RX, SFDX2_TX, SRX2_RX, SRX2_TX, LED_RX2, LED_TXRX2_RX, LED_TXRX2_TX} = fe1_gpio;

  wire [31:0] misc_outs; 
  reg  [31:0] misc_outs_r;
  always @(posedge bus_clk) begin
    misc_outs_r <= misc_outs; // register misc ios to ease routing to flop
  end
  wire mimo_dummy;
  wire codec_arst;
  assign {swap_atr_n, tx_bandsel_a, tx_bandsel_b, rx_bandsel_a, rx_bandsel_b, rx_bandsel_c, codec_arst, mimo_dummy, ref_sel } = misc_outs_r[8:0];
  assign codec_ctrl_in = 4'b1;
  assign codec_en_agc  = 1'b1;
  assign codec_txrx    = 1'b1;
  assign codec_enable  = 1'b1;
  assign codec_reset   = ~codec_arst; // Codec Reset // RESETB // Operates active-low
  assign codec_sync    = 1'b0;

  ///////////////////////////////////////////////////////////////////////
  // b200 core (SPI/register control only, data path disconnected)
  //
  // b200_core handles:
  //   - USB transport (GPIF2 <-> AXI stream)
  //   - SPI master for AD9361 register read/write
  //   - misc_outs (frontend ATR, codec reset, band select, etc.)
  //   - Timing (PPS)
  //
  // Radio data path is NOT used:
  //   - rx0/rx1: fed with zeros (no ADC data goes to USB)
  //   - tx0/tx1: outputs ignored (no USB data goes to DAC)
  ///////////////////////////////////////////////////////////////////////
  wire [ 9:0] fp_gpio_in, fp_gpio_out, fp_gpio_ddr;
  wire [31:0] tx_data0, tx_data1;
  wire [31:0] rx_data0, rx_data1;
  assign rx_data0 = tx_data0;
  assign rx_data1 = tx_data1;

  b200_core #(
    .EXTRA_BUFF_SIZE(12)
  ) b200_core (
    .bus_clk(bus_clk),
    .bus_rst(bus_rst),
    .tx_tdata(tx_tdata), .tx_tlast(tx_tlast), .tx_tvalid(tx_tvalid), .tx_tready(tx_tready),
    .rx_tdata(rx_tdata), .rx_tlast(rx_tlast),  .rx_tvalid(rx_tvalid), .rx_tready(rx_tready),
    .ctrl_tdata(ctrl_tdata), .ctrl_tlast(ctrl_tlast),  .ctrl_tvalid(ctrl_tvalid), .ctrl_tready(ctrl_tready),
    .resp_tdata(resp_tdata), .resp_tlast(resp_tlast),  .resp_tvalid(resp_tvalid), .resp_tready(resp_tready),
    .radio_clk(radio_clk), .radio_rst(radio_rst),
    .rx0(rx_data0), .rx1(rx_data1),
    .tx0(tx_data0), .tx1(tx_data1),
    .fe0_gpio_out(radio0_gpio), .fe1_gpio_out(radio1_gpio),
    .fp_gpio_in(fp_gpio_in), .fp_gpio_out(fp_gpio_out), .fp_gpio_ddr(fp_gpio_ddr),
    .pps_int(PPS_IN_INT), .pps_ext(PPS_IN_EXT),
    .rxd(gps_txd), .txd(gps_rxd),
    .sclk(sclk), .sen(sen), .mosi(mosi), .miso(miso),
    .rb_misc({31'b0, pll_lock}), .misc_outs(misc_outs),
    .debug_scl(GPIF_CTL8), .debug_sda(GPIF_CTL6),
`ifdef DEBUG_UART
    .debug_txd(FPGA_TXD0), .debug_rxd(FPGA_RXD0),
`else
    .debug_txd(), .debug_rxd(1'b0),
`endif
    .lock_signals(codec_ctrl_out[7:6]),
    .debug()
  );

`ifdef TARGET_B210
  `ifdef DEBUG_UART
  gpio_atr_io #(
    .WIDTH(8)
  ) gpio_atr_io_inst (   // B210 with UART
    .clk(radio_clk), 
    .gpio_pins(fp_gpio),
    .gpio_ddr(fp_gpio_ddr[7:0]), 
    .gpio_out(fp_gpio_out[7:0]),
    .gpio_in(fp_gpio_in[7:0])
  );
  assign fp_gpio_in[9:8] = 2'b00;
  `else
  gpio_atr_io #(
    .WIDTH(10)
  ) gpio_atr_io_inst (  // B210 no UART
    .clk(radio_clk), 
    .gpio_pins({FPGA_RXD0, FPGA_TXD0, fp_gpio}),
    .gpio_ddr(fp_gpio_ddr), 
    .gpio_out(fp_gpio_out), 
    .gpio_in(fp_gpio_in)
  );
  `endif
`else
  `ifdef DEBUG_UART
  assign fp_gpio_in = 10'h000; // B200 with UART
  `else
  gpio_atr_io #(
    .WIDTH(2)
  ) gpio_atr_io_inst ( // B200 no UART
    .clk(radio_clk), 
    .gpio_pins({FPGA_RXD0, FPGA_TXD0}),
    .gpio_ddr(fp_gpio_ddr[9:8]), 
    .gpio_out(fp_gpio_out[9:8]), 
    .gpio_in(fp_gpio_in[9:8])
  );
  assign fp_gpio_in[7:0] = 8'h00;
  `endif
`endif

  ///////////////////////////////////////////////////////////////////////
  // GPIF2
  ///////////////////////////////////////////////////////////////////////
  gpif2_slave_fifo32 #(
    .DATA_RX_FIFO_SIZE(13), 
    .DATA_TX_FIFO_SIZE(13)
  ) slave_fifo32 (
    .gpif_clk(gpif_clk), .gpif_rst(gpif_rst), .gpif_enb(1'b1),
    .gpif_ctl({GPIF_CTL8, GPIF_CTL6, GPIF_CTL5, GPIF_CTL4}), 
    .fifoadr({GPIF_CTL11,GPIF_CTL12}),
    .slwr(GPIF_CTL1), .sloe(GPIF_CTL2), .slcs(GPIF_CTL0), .slrd(GPIF_CTL3), 
    .pktend(GPIF_CTL7),
    .gpif_d(GPIF_D),
    .fifo_clk(bus_clk), 
    .fifo_rst(bus_rst),
    .tx_tdata(tx_tdata), .tx_tlast(tx_tlast), .tx_tvalid(tx_tvalid), .tx_tready(tx_tready),
    .rx_tdata(rx_tdata), .rx_tlast(rx_tlast),  .rx_tvalid(rx_tvalid), .rx_tready(rx_tready),
    .ctrl_tdata(ctrl_tdata), .ctrl_tlast(ctrl_tlast),  .ctrl_tvalid(ctrl_tvalid), .ctrl_tready(ctrl_tready),
    .resp_tdata(resp_tdata), .resp_tlast(resp_tlast),  .resp_tvalid(resp_tvalid), .resp_tready(resp_tready),
    .debug()
  );

endmodule // B200
