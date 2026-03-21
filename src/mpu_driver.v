`default_nettype none

module mpu_driver #(
    parameter CLK_DIV = 5,
    parameter SAMPLE_RATE_HZ = 100, // 100Hz sample rate
    parameter SYS_CLK_FREQ = 10000000,
    // Timer for sample rate
`ifdef FAST_SIM
    parameter TIMER_LIMIT = 20,
    parameter INIT_WAIT_CYCLES = 10
`else
    parameter TIMER_LIMIT = SYS_CLK_FREQ / SAMPLE_RATE_HZ,
    // Timer for initialization wait (100ms and 200ms)
    parameter INIT_WAIT_100MS = SYS_CLK_FREQ / 10,
    parameter INIT_WAIT_200MS = SYS_CLK_FREQ / 5
`endif
)(
    input  wire        clk,
    input  wire        rst_n,

    // SPI Interface
    input  wire        spi_miso, // from MPU
    output wire        spi_mosi, // to MPU
    output wire        spi_sclk,
    output reg         spi_cs_n,

    // Sensor Data Output
    output reg  signed [15:0] accel_x,
    output reg  signed [15:0] accel_y,
    output reg  signed [15:0] accel_z,
    output reg  signed [15:0] gyro_x,
    output reg  signed [15:0] gyro_y,
    output reg  signed [15:0] gyro_z,
    output reg         valid
);

    // MPU-6500 Registers
    localparam MPU_PWR_MGMT_1   = 8'h6B;
    localparam MPU_WHO_AM_I     = 8'h75;

    // Register Addresses for reading
    wire [7:0] REG_ADDRS [0:5];
    assign REG_ADDRS[0] = 8'h3B; // ACCEL_XOUT_H
    assign REG_ADDRS[1] = 8'h3D; // ACCEL_YOUT_H
    assign REG_ADDRS[2] = 8'h3F; // ACCEL_ZOUT_H
    assign REG_ADDRS[3] = 8'h43; // GYRO_XOUT_H
    assign REG_ADDRS[4] = 8'h45; // GYRO_YOUT_H
    assign REG_ADDRS[5] = 8'h47; // GYRO_ZOUT_H

    // States
    localparam S_INIT          = 0;
    localparam S_RST_1         = 1;
    localparam S_RST_1_WAIT    = 2;
    localparam S_RST_2         = 3;
    localparam S_RST_2_WAIT    = 4;
    localparam S_RST_DELAY     = 5;
    localparam S_WAKE_1        = 6;
    localparam S_WAKE_1_WAIT   = 7;
    localparam S_WAKE_2        = 8;
    localparam S_WAKE_2_WAIT   = 9;
    localparam S_WAKE_DELAY    = 10;
    localparam S_IDLE          = 11;

    localparam S_READ_START    = 12;
    localparam S_READ_CMD      = 13;
    localparam S_READ_CMD_WAIT = 14;
    localparam S_READ_H        = 15;
    localparam S_READ_H_WAIT   = 16;
    localparam S_READ_L        = 17;
    localparam S_READ_L_WAIT   = 18;
    localparam S_READ_NEXT     = 19;

    localparam S_UPDATE        = 20;

    reg [4:0]  state;
    reg [2:0]  read_idx;
    reg [31:0] timer;
    reg        spi_start;
    reg [7:0]  spi_data_in;
    wire [7:0] spi_data_out;
    wire       spi_busy;
    wire       spi_done;

    reg [7:0]  temp_h;

`ifdef FAST_SIM
    wire [31:0] delay_100ms = 10;
    wire [31:0] delay_200ms = 20;
`else
    wire [31:0] delay_100ms = INIT_WAIT_100MS;
    wire [31:0] delay_200ms = INIT_WAIT_200MS;
`endif

    // SPI Master Instance
    spi_master #(
        .CLK_DIV(CLK_DIV)
    ) spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .data_in(spi_data_in),
        .miso(spi_miso),
        .mosi(spi_mosi),
        .sclk(spi_sclk),
        .busy(spi_busy),
        .done(spi_done),
        .data_out(spi_data_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_INIT;
            timer       <= 0;
            spi_cs_n    <= 1;
            spi_start   <= 0;
            read_idx    <= 0;
            valid       <= 0;
            accel_x     <= 0;
            accel_y     <= 0;
            accel_z     <= 0;
            gyro_x      <= 0;
            gyro_y      <= 0;
            gyro_z      <= 0;
            temp_h      <= 0;
            spi_data_in <= 0;
        end else begin
            // Default signals
            valid <= 0;
            spi_start <= 0;

            case (state)
                S_INIT: begin
                    state <= S_RST_1;
                end

                S_RST_1: begin
                    // Write PWR_MGMT_1 (0x6B) to 0x80 (Reset)
                    spi_cs_n    <= 0;
                    spi_data_in <= MPU_PWR_MGMT_1;
                    spi_start   <= 1;
                    state       <= S_RST_1_WAIT;
                end

                S_RST_1_WAIT: begin
                    if (spi_done) begin
                        state <= S_RST_2;
                    end
                end

                S_RST_2: begin
                    spi_data_in <= 8'h80;
                    spi_start   <= 1;
                    state       <= S_RST_2_WAIT;
                end

                S_RST_2_WAIT: begin
                    if (spi_done) begin
                        spi_cs_n <= 1; // Deassert CS
                        timer    <= 0;
                        state    <= S_RST_DELAY;
                    end
                end

                S_RST_DELAY: begin
                    // Wait 100ms
                    if (timer >= delay_100ms) begin
                        state <= S_WAKE_1;
                        timer <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_WAKE_1: begin
                    // Write PWR_MGMT_1 (0x6B) to 0x01
                    spi_cs_n    <= 0;
                    spi_data_in <= MPU_PWR_MGMT_1;
                    spi_start   <= 1;
                    state       <= S_WAKE_1_WAIT;
                end

                S_WAKE_1_WAIT: begin
                    if (spi_done) begin
                        state <= S_WAKE_2;
                    end
                end

                S_WAKE_2: begin
                    spi_data_in <= 8'h01;
                    spi_start   <= 1;
                    state       <= S_WAKE_2_WAIT;
                end

                S_WAKE_2_WAIT: begin
                    if (spi_done) begin
                        spi_cs_n <= 1; // Deassert CS
                        timer    <= 0;
                        state    <= S_WAKE_DELAY;
                    end
                end

                S_WAKE_DELAY: begin
                    // Wait 200ms
                    if (timer >= delay_200ms) begin
                        state <= S_IDLE;
                        timer <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_IDLE: begin
                    if (timer >= TIMER_LIMIT) begin
                        read_idx <= 0;
                        state <= S_READ_START;
                        timer <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_READ_START: begin
                    spi_cs_n    <= 0;
                    spi_data_in <= REG_ADDRS[read_idx] | 8'h80; // Read bit (MSB 1)
                    spi_start   <= 1;
                    state       <= S_READ_CMD_WAIT;
                end

                S_READ_CMD_WAIT: begin
                    if (spi_done) begin
                        state <= S_READ_H;
                    end
                end

                S_READ_H: begin
                    spi_data_in <= 8'h00; // Dummy
                    spi_start   <= 1;
                    state       <= S_READ_H_WAIT;
                end

                S_READ_H_WAIT: begin
                    if (spi_done) begin
                        temp_h <= spi_data_out;
                        state  <= S_READ_L;
                    end
                end

                S_READ_L: begin
                    spi_data_in <= 8'h00; // Dummy
                    spi_start   <= 1;
                    state       <= S_READ_L_WAIT;
                end

                S_READ_L_WAIT: begin
                    if (spi_done) begin
                        spi_cs_n <= 1; // Deassert CS!

                        case (read_idx)
                            0: accel_x <= {temp_h, spi_data_out};
                            1: accel_y <= {temp_h, spi_data_out};
                            2: accel_z <= {temp_h, spi_data_out};
                            3: gyro_x  <= {temp_h, spi_data_out};
                            4: gyro_y  <= {temp_h, spi_data_out};
                            5: gyro_z  <= {temp_h, spi_data_out};
                        endcase

                        state <= S_READ_NEXT;
                    end
                end

                S_READ_NEXT: begin
                    if (read_idx == 5) begin
                        state <= S_UPDATE;
                    end else begin
                        read_idx <= read_idx + 1;
                        state    <= S_READ_START;
                    end
                end

                S_UPDATE: begin
                    valid <= 1;
                    state <= S_IDLE;
                end
                default: state <= S_INIT;
            endcase
        end
    end

endmodule
