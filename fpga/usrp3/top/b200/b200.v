//
// Copyright 2013 Ettus Research LLC
// Copyright 2017 Ettus Research, a National Instruments Company
//
// SPDX-License-Identifier: LGPL-3.0-or-later
//

/***********************************************************
 * B200 Module Declaration
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
  wire rx_data_clock;
  wire locked;
  b200_clk_gen gen_clks (
    .CLK_IN1_40_P(codec_main_clk_p), 
    .CLK_IN1_40_N(codec_main_clk_n),
    .CLK_OUT1_40_int(rx_data_clock), 
    .CLK_OUT2_100_gpif(gpif_clk), 
    .CLK_OUT3_100_bus(),
    .RESET(reset_global), 
    .LOCKED(locked)
  );

  // Generate 30MHz clock from the 40MHz rx_data_clock
  wire rx_data_clock_30;
  wire dcm30_clkfx;
  wire dcm30_locked;

  reg [3:0] dcm30_rst_reg = 4'b1111;
  always @(posedge rx_data_clock or posedge reset_global) begin
    if (reset_global) begin
      dcm30_rst_reg <= 4'b1111;
    end else begin
      dcm30_rst_reg <= {dcm30_rst_reg[2:0], 1'b0};
    end
  end
  wire dcm30_rst = dcm30_rst_reg[3];

  DCM_SP #(
    .CLKDV_DIVIDE(2.0),
    .CLKFX_DIVIDE(4),
    .CLKFX_MULTIPLY(3),
    .CLKIN_DIVIDE_BY_2("FALSE"),
    .CLKIN_PERIOD(25.0),
    .CLKOUT_PHASE_SHIFT("NONE"),
    .CLK_FEEDBACK("NONE"),
    .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"),
    .PHASE_SHIFT(0),
    .STARTUP_WAIT("FALSE")
  ) dcm_sp_30 (
    .CLKIN(rx_data_clock),
    .CLKFB(1'b0),
    .CLK0(),
    .CLK90(),
    .CLK180(),
    .CLK270(),
    .CLK2X(),
    .CLK2X180(),
    .CLKFX(dcm30_clkfx),
    .CLKFX180(),
    .CLKDV(),
    .PSCLK(1'b0),
    .PSEN(1'b0),
    .PSINCDEC(1'b0),
    .PSDONE(),
    .LOCKED(dcm30_locked),
    .STATUS(),
    .RST(dcm30_rst),
    .DSSEN(1'b0)
  );

  BUFG bufg_30 (
    .I(dcm30_clkfx),
    .O(rx_data_clock_30)
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
  wire [1:0] debug_clk_int;
  // assign debug_clk[1:0] = 2'b0; // Removed to allow loopback logic to drive debug_clk
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

  wire        tx_data_clock;
  wire        tx_data_frame;
  wire        tx_data_valid;
  wire [11:0] tx_data;
  wire        btn_reset;
  assign tx_data_clock = debug_clk[0];
  assign tx_data_frame = debug[31];
  assign tx_data_valid = debug[30];
  assign tx_data[11]   = debug[29];
  assign tx_data[10]   = debug[28];
  assign tx_data[ 9]   = debug[27];
  assign tx_data[ 8]   = debug[26];
  assign tx_data[ 7]   = debug[25];
  assign tx_data[ 6]   = debug[24];
  assign tx_data[ 5]   = debug[23];
  assign tx_data[ 4]   = debug[22];
  assign tx_data[ 3]   = debug[21];
  assign tx_data[ 2]   = debug[20];
  assign tx_data[ 1]   = debug[19];
  assign tx_data[ 0]   = debug[18];
  assign btn_reset     = debug[17];
  assign debug[16]     = 1'bz;

  reg         rx_data_frame;
  reg         rx_data_valid;
  reg  [11:0] rx_data;
  S6CLK2PIN S6CLK2PIN_debug_clk1 (
    .I(radio_clk), 
    .O(debug_clk[1])
  );
  assign debug[15]    = rx_data_frame;
  assign debug[14]    = rx_data_valid;
  assign debug[13]    = rx_data[11];
  assign debug[12]    = rx_data[10];
  assign debug[11]    = rx_data[ 9];
  assign debug[10]    = rx_data[ 8];
  assign debug[ 9]    = rx_data[ 7];
  assign debug[ 8]    = rx_data[ 6];
  assign debug[ 7]    = rx_data[ 5];
  assign debug[ 6]    = rx_data[ 4];
  assign debug[ 5]    = rx_data[ 3];
  assign debug[ 4]    = rx_data[ 2];
  assign debug[ 3]    = rx_data[ 1];
  assign debug[ 2]    = rx_data[ 0];
  assign debug[ 1]    = 1'bz;
  assign debug[ 0]    = 1'bz;

  reg         tx_data_clock_r0, tx_data_clock_r1, tx_data_clock_r2;
  reg         tx_data_frame_r0, tx_data_frame_r1;
  reg         tx_data_valid_r0, tx_data_valid_r1, tx_data_valid_r2, tx_data_valid_safe;
  reg  [11:0] tx_data_r0, tx_data_r1, tx_data_re_r2, tx_data_im_r2, tx_data_re_safe, tx_data_im_safe;
  always @(posedge bus_clk) begin
    if (btn_reset == 1'b1) begin
      tx_data_clock_r0   <= 1'b0;
      tx_data_clock_r1   <= 1'b0;
      tx_data_clock_r2   <= 1'b0;
      tx_data_frame_r0   <= 1'b0;
      tx_data_frame_r1   <= 1'b0;
      tx_data_valid_r0   <= 1'b0;
      tx_data_valid_r1   <= 1'b0;
      tx_data_valid_r2   <= 1'b0;
      tx_data_valid_safe <= 1'b0;
      tx_data_r0         <= 12'b000000000000;
      tx_data_r1         <= 12'b000000000000;
      tx_data_re_r2      <= 12'b000000000000;
      tx_data_im_r2      <= 12'b000000000000;
      tx_data_re_safe    <= 12'b000000000000;
      tx_data_im_safe    <= 12'b000000000000;
    end else begin
      tx_data_clock_r0 <= tx_data_clock;
      tx_data_clock_r1 <= tx_data_clock_r0;
      tx_data_clock_r2 <= tx_data_clock_r1;
      tx_data_frame_r0 <= tx_data_frame;
      tx_data_frame_r1 <= tx_data_frame_r0;
      tx_data_valid_r0 <= tx_data_valid;
      tx_data_valid_r1 <= tx_data_valid_r0;
      tx_data_r0       <= tx_data;
      tx_data_r1       <= tx_data_r0;
      if (tx_data_clock_r2 == 1'b0 && tx_data_clock_r1 == 1'b1) begin
        tx_data_valid_r2 <= tx_data_valid_r1;
        if (tx_data_frame_r1 == 1'b1) begin
          tx_data_re_r2 <= tx_data_r1;
          tx_data_valid_safe <= tx_data_valid_r2;
          tx_data_re_safe    <= tx_data_re_r2;
          tx_data_im_safe    <= tx_data_im_r2;
        end else begin
          tx_data_im_r2 <= tx_data_r1;
        end
      end
    end
  end

  wire [11:0] tx_i0, tx_q0, tx_i1, tx_q1;
  assign tx_i0 = tx_data_re_safe;
  assign tx_q0 = tx_data_im_safe;
  assign tx_i1 = 12'h000;
  assign tx_q1 = 12'h000;

  wire [11:0] rx_i0, rx_q0, rx_i1, rx_q1;

  // -------------------------------------------------------------
  // Real-World Packet Envelope Detector with Hold Timer
  // -------------------------------------------------------------
  wire [11:0] abs_rx_i0 = rx_i0[11] ? -rx_i0 : rx_i0;
  wire [11:0] abs_rx_q0 = rx_q0[11] ? -rx_q0 : rx_q0;
  wire [12:0] rx_mag    = abs_rx_i0 + abs_rx_q0;
  
  // Threshold to distinguish signal from background noise
  // AD9361 noise floor is typically ~30-50 LSB; set well above that
  wire threshold_exceeded = (rx_mag > 13'h00C8); // 200 decimal
  
  // Hold timer to bridge across valid zeros in the payload
  reg [15:0] hold_timer = 16'd0;
  reg  [11:0] rx_data_re, rx_data_im;
  
  always @(negedge radio_clk) begin
    if (btn_reset == 1'b1) begin
      rx_data_re    <= 12'h000;
      rx_data_im    <= 12'h000;
      rx_data       <= 12'h000;
      rx_data_frame <= 1'b0;
      rx_data_valid <= 1'b0;
      hold_timer    <= 16'd0;
    end else begin
      if (rx_data_frame == 1'b0) begin
        rx_data_re    <= rx_i0;
        rx_data_im    <= rx_q0;
        rx_data       <= rx_i0;
        rx_data_frame <= 1'b1;
      end else begin
        rx_data       <= rx_data_im;
        rx_data_frame <= 1'b0;
      end
      // Packet Envelope Logic
      if (threshold_exceeded) begin
        // Energy detected! Assert valid and reset timer
        rx_data_valid <= 1'b1;
        hold_timer <= 16'd100; // Hold for 100 samples
      end else if (hold_timer > 0) begin
        // No energy, but timer is running. Keep valid High and countdown!
        rx_data_valid <= 1'b1;
        hold_timer <= hold_timer - 1'b1;
      end else begin
        // No energy and timer expired. Packet is definitely over.
        rx_data_valid <= 1'b0;
      end
    end
  end

  wire mimo = 1'b0;
   
  b200_io b200_io_i0 (
    .reset(reset),
    .mimo(mimo),
    
    // Baseband sample interface
    .radio_clk(radio_clk),
    .rx_i0(rx_i0), 
    .rx_q0(rx_q0), 
    .rx_i1(rx_i1), 
    .rx_q1(rx_q1),
    .tx_i0(tx_i0), 
    .tx_q0(tx_q0), 
    .tx_i1(tx_i1), 
    .tx_q1(tx_q1),
    
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
  // b200 core
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
