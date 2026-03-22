`default_nettype none

module tt_um_intv0id_kalman #(
    parameter CLK_FREQ = 10000000 // Default 10MHz
)(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // SPI Pins
    wire spi_miso = uio_in[0];
    wire spi_mosi;
    wire spi_sclk;
    wire spi_cs_n;

    // UART Pin
    wire uart_tx_out;

    // Assign Outputs
    assign uo_out[0] = spi_mosi;
    assign uo_out[1] = spi_sclk;
    assign uo_out[2] = spi_cs_n;
    assign uo_out[3] = uart_tx_out;
    assign uo_out[7:4] = 0;

    assign uio_out = 0;
    assign uio_oe  = 0;

    // Internal Signals
    wire signed [15:0] accel_x, accel_y, accel_z;
    wire signed [15:0] gyro_x, gyro_y;
    wire mpu_valid;

    // Helper localparam for CLK_DIV
`ifdef FAST_SIM
    localparam CLK_DIV = 2;
`else
    localparam CLK_DIV = CLK_FREQ / 400000; // Target 200kHz SPI clock
`endif

    // MPU Driver
    mpu_driver #(
        .CLK_DIV(CLK_DIV), // Use calculated parameter below
        .SAMPLE_RATE_HZ(100),
        .SYS_CLK_FREQ(CLK_FREQ)
    ) mpu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .spi_miso(spi_miso),
        .spi_mosi(spi_mosi),
        .spi_sclk(spi_sclk),
        .spi_cs_n(spi_cs_n),
        .accel_x(accel_x),
        .accel_y(accel_y),
        .accel_z(accel_z),
        .gyro_x(gyro_x),
        .gyro_y(gyro_y),
        .valid(mpu_valid)
    );

    // CORDIC Shared Instance
    reg cordic_start;
    wire signed [15:0] cordic_x = (state == S_CALC_ROLL || state == S_WAIT_ROLL) ? (accel_z >>> 1) : mag_yz;
    wire signed [15:0] cordic_y = (state == S_CALC_ROLL || state == S_WAIT_ROLL) ? (accel_y >>> 1) : -accel_x_scaled;
    wire signed [15:0] cordic_angle, cordic_mag;
    wire cordic_done;

    cordic #(
        .WIDTH(8),
        .STAGES(8)
    ) cordic_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(cordic_start),
        // Truncate inputs to 12 bits internally
        .x_in(cordic_x),
        .y_in(cordic_y),
        .angle_out(cordic_angle),
        .mag_out(cordic_mag),
        .done(cordic_done),
        .busy()
    );

    // Kalman Instances
    reg kalman_en;
    wire signed [15:0] kalman_rate_roll = gyro_x;
    wire signed [15:0] kalman_angle_m_roll = roll_m;
    wire signed [15:0] roll_est;

    kalman kalman_roll (
        .clk(clk),
        .rst_n(rst_n),
        .en(kalman_en),
        .rate(kalman_rate_roll),
        .angle_m(kalman_angle_m_roll),
        .angle_out(roll_est)
    );

    wire signed [15:0] kalman_rate_pitch = gyro_y;
    wire signed [15:0] kalman_angle_m_pitch = pitch_m;
    wire signed [15:0] pitch_est;

    kalman kalman_pitch (
        .clk(clk),
        .rst_n(rst_n),
        .en(kalman_en),
        .rate(kalman_rate_pitch),
        .angle_m(kalman_angle_m_pitch),
        .angle_out(pitch_est)
    );

    // Processing State Machine
    localparam S_IDLE       = 0;
    localparam S_CALC_ROLL  = 1;
    localparam S_WAIT_ROLL  = 2;
    localparam S_CALC_PITCH = 3;
    localparam S_WAIT_PITCH = 4;
    localparam S_UPDATE_K   = 5;
    localparam S_SEND_UART  = 6;
    localparam S_WAIT_UART  = 7;

    reg [3:0] state;
    reg signed [15:0] roll_m, mag_yz;
    reg signed [15:0] pitch_m;

    // Scaled accel_x for Pitch calculation
    // Scale factor 0.8125 ~ K/2 (where K=1.647, K/2=0.823)
    // (x >> 1) + (x >> 2) + (x >> 4)
    wire signed [15:0] accel_x_scaled = (accel_x >>> 1) + (accel_x >>> 2) + (accel_x >>> 4);

    // UART Signals

    wire [7:0] uart_data;
    assign uart_data = (uart_cnt == 0) ? 8'hDE :
                       (uart_cnt == 1) ? 8'hAD :
                       (uart_cnt == 2) ? roll_est[15:8] :
                       (uart_cnt == 3) ? roll_est[7:0] :
                       (uart_cnt == 4) ? pitch_est[15:8] :
                       pitch_est[7:0];
    reg uart_start;
    wire uart_busy, uart_done;
    reg [3:0] uart_cnt;

    // Helper localparam for BAUD_DIV
`ifdef FAST_SIM
    localparam BAUD_DIV_PARAM = 5;
`else
    localparam BAUD_DIV_PARAM = CLK_FREQ / 115200;
`endif

    uart_tx #(
        .BAUD_DIV(BAUD_DIV_PARAM)
    ) uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(uart_start),
        .data_in(uart_data),
        .tx(uart_tx_out),
        .busy(uart_busy),
        .done(uart_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cordic_start <= 0;
            kalman_en <= 0;
            uart_start <= 0;
            roll_m <= 0;
            mag_yz <= 0;
            pitch_m <= 0;
            uart_cnt <= 0;
        end else begin
            cordic_start <= 0;
            kalman_en <= 0;
            // uart_start handled in S_SEND_UART

            case (state)
                S_IDLE: begin
                    if (mpu_valid) begin
                        state <= S_CALC_ROLL;
                    end
                end

                S_CALC_ROLL: begin
                    // Roll = atan2(accel_y, accel_z)
                    // Inputs scaled by 1/2 to avoid overflow
                    cordic_start <= 1;
                    state <= S_WAIT_ROLL;
                end

                S_WAIT_ROLL: begin
                    if (cordic_done) begin
                        roll_m <= cordic_angle;
                        mag_yz <= cordic_mag; // Scale: K/2
                        state  <= S_CALC_PITCH;
                    end
                end

                S_CALC_PITCH: begin
                    // Pitch = atan2(-accel_x, sqrt(y^2+z^2))
                    // Input x: mag_yz (Scale K/2)
                    // Input y: -accel_x scaled by K/2
                    cordic_start <= 1;
                    state <= S_WAIT_PITCH;
                end

                S_WAIT_PITCH: begin
                    if (cordic_done) begin
                        pitch_m <= cordic_angle;
                        state   <= S_UPDATE_K;
                    end
                end

                S_UPDATE_K: begin
                    // Update Kalman Filters


                    kalman_en <= 1;
                    uart_cnt <= 0;
                    state <= S_SEND_UART;
                end

                S_SEND_UART: begin
                    if (!uart_busy && !uart_start) begin
                        uart_start <= 1;

                        state <= S_WAIT_UART;
                    end else if (uart_start) begin
                        uart_start <= 0; // Clear start
                    end
                end

                S_WAIT_UART: begin
                    uart_start <= 0;
                    if (uart_done) begin
                        if (uart_cnt == 5) begin
                            state <= S_IDLE;
                        end else begin
                            uart_cnt <= uart_cnt + 1;
                            state <= S_SEND_UART;
                        end
                    end
                end
            endcase
        end
    end

endmodule
