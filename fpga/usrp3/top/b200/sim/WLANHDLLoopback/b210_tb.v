`timescale 1ns/1ps

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
  always #(1000/100/2) tx_clock = ~tx_clock; // 100 MHz
  always #(1000/50/2) rx_clock = ~rx_clock; // 50 MHz

  wire        tx_bits_enable;
  wire [ 7:0] tx_bits_in = 8'b11001100;
  wire        tx_data_clock;
  wire        tx_data_valid;
  wire [15:0] tx_data_re;
  wire [15:0] tx_data_im;

  reg         rx_data_clock;
  reg         rx_data_valid;
  reg  [15:0] rx_data_re;
  reg  [15:0] rx_data_im;
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
    .tx_data_valid(tx_data_valid), 
    .tx_data_re(tx_data_re), 
    .tx_data_im(tx_data_im),
    .rx_clock(rx_clock), 
    .rx_data_clock(rx_data_clock), 
    .rx_data_valid(rx_data_valid),
    .rx_data_re(rx_data_re),
    .rx_data_im(rx_data_im),
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

  reg        tx_data_clock_r0, tx_data_clock_r1, tx_data_clock_r2;
  reg        tx_data_valid_r0, tx_data_valid_r1, tx_data_valid_safe;
  reg [16:0] tx_data_re_r0, tx_data_re_r1, tx_data_re_safe;
  reg [16:0] tx_data_im_r0, tx_data_im_r1, tx_data_im_safe;
  always @(posedge tx_clock) begin
    if (btn_reset == 1'b1) begin
      tx_data_clock_r0   <= 1'b0;
      tx_data_clock_r1   <= 1'b0;
      tx_data_clock_r2   <= 1'b0;
      tx_data_valid_r0   <= 1'b0;
      tx_data_valid_r1   <= 1'b0;
      tx_data_valid_safe <= 1'b0;
      tx_data_re_r0      <= 16'b0000000000000000;
      tx_data_re_r1      <= 16'b0000000000000000;
      tx_data_re_safe    <= 16'b0000000000000000;
      tx_data_im_r0      <= 16'b0000000000000000;
      tx_data_im_r1      <= 16'b0000000000000000;
      tx_data_im_safe    <= 16'b0000000000000000;
    end else begin
      tx_data_clock_r0 <= tx_data_clock;
      tx_data_clock_r1 <= tx_data_clock_r0;
      tx_data_clock_r2 <= tx_data_clock_r1;
      tx_data_valid_r0 <= tx_data_valid;
      tx_data_valid_r1 <= tx_data_valid_r0;
      tx_data_re_r0    <= tx_data_re;
      tx_data_re_r1    <= tx_data_re_r0;
      tx_data_im_r0    <= tx_data_im;
      tx_data_im_r1    <= tx_data_im_r0;
      if (tx_data_clock_r2 == 1'b0 && tx_data_clock_r1 == 1'b1) begin
        tx_data_valid_safe <= tx_data_valid_r1;
        tx_data_re_safe    <= tx_data_re_r1;
        tx_data_im_safe    <= tx_data_im_r1;
      end
    end
  end

  wire [11:0] tx_i0, tx_q0, tx_i1, tx_q1;
  assign tx_i0 = tx_data_re_safe[15:4];
  assign tx_q0 = tx_data_im_safe[15:4];
  assign tx_i1 = 12'h000;
  assign tx_q1 = 12'h000;

  wire [11:0] rx_i0, rx_q0, rx_i1, rx_q1;
  wire        rx_data_valid_node;

  // -------------------------------------------------------------
  // Real-World Packet Envelope Detector with Hold Timer
  // -------------------------------------------------------------
  wire [11:0] abs_rx_i0 = rx_i0[11] ? -rx_i0 : rx_i0;
  wire [11:0] abs_rx_q0 = rx_q0[11] ? -rx_q0 : rx_q0;
  wire [12:0] rx_mag    = abs_rx_i0 + abs_rx_q0;
  
  // Threshold to distinguish signal from background noise (adjust as needed)
  wire threshold_exceeded = (rx_mag > 13'd20); 
  
  // Hold timer to bridge across valid zeros in the payload
  reg [15:0] hold_timer = 16'd0;

  reg  [ 2:0] rx_data_clock_count;
  always @(posedge rx_clock) begin
    // Clock generation block
    if (btn_reset == 1'b1) begin
      rx_data_clock_count <= 3'b000;
      rx_data_clock <= 1'b0;
    end else begin
      rx_data_clock_count <= rx_data_clock_count + 1'b1;
      if (rx_data_clock_count == 3'b000) begin
        rx_data_clock <= 1'b0;
      end else if (rx_data_clock_count == 3'b100) begin
        rx_data_clock <= 1'b1;
      end
    end
    
    // Data reception and valid envelope generation block
    if (btn_reset == 1'b1) begin
      rx_data_re <= 16'h0000;
      rx_data_im <= 16'h0000;
      rx_data_valid <= 1'b0;
      hold_timer <= 16'd0;
    end else if (rx_data_valid_node == 1'b0) begin
      rx_data_re <= 16'h0000;
      rx_data_im <= 16'h0000;
      rx_data_valid <= 1'b0;
      hold_timer <= 16'd0;
    end else if (rx_data_clock_count == 3'b000) begin
      // Assign the data
      rx_data_re <= {rx_i0, 4'h0};
      rx_data_im <= {rx_q0, 4'h0};

      // Packet Envelope Logic
      if (threshold_exceeded) begin
        // Energy detected! Assert valid and reset timer
        rx_data_valid <= 1'b1;
        hold_timer <= 16'd400; // Hold for 400 samples (covers long zero-gaps)
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

  wire        mimo = 1'b0;

  wire        tx_clk;
  wire        tx_frame;
  wire [11:0] tx_data;
  reg         rx_clk = 1'b0;
  always #(20/2) rx_clk = ~rx_clk;
  wire        rx_frame = tx_frame;
  wire [11:0] rx_data  = tx_data;

  reg         tb_clk = 1'b0;
  always #(10/2) tb_clk = ~tb_clk;
  wire        radio_clk;

  b200_io b200_io_0 (
    .reset(btn_reset),
    .mimo(mimo),

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
    .strobe(rx_data_valid_node),

    .rx_clk(rx_clk),
    .rx_frame(rx_frame),
    .rx_data(rx_data),
    .tx_clk(tx_clk),
    .tx_frame(tx_frame),
    .tx_data(tx_data)
  );

  initial begin
    // ---- VCD出力設定を追加 ----
    $dumpfile("b210_simulation.vcd"); // 保存されるファイル名
    $dumpvars(0, b210_tb);            // b210_tb 以下のすべての階層の信号をダンプ
    // --------------------------
    #(100) btn_reset <= 1; btn_tx_start <= 0; btn_rx_start <= 0;
    #(100) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    #(100) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 1;
    #(100) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    #(100) btn_reset <= 0; btn_tx_start <= 1; btn_rx_start <= 0;
    #(100) btn_reset <= 0; btn_tx_start <= 0; btn_rx_start <= 0;
    #(1000000) $finish;
  end

endmodule
