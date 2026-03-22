`default_nettype none

module mpu_driver #(
    parameter CLK_DIV = 5,
    parameter SAMPLE_RATE_HZ = 100, // 100Hz sample rate
    parameter SYS_CLK_FREQ = 10000000,
    // Timer for sample rate
`ifdef FAST_SIM
    parameter TIMER_LIMIT = 20,
    parameter INIT_WAIT_100MS = 10,
    parameter INIT_WAIT_200MS = 20
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
    output wire        spi_cs_n,

    // Sensor Data Output
    output reg  signed [15:0] accel_x,
    output reg  signed [15:0] accel_y,
    output reg  signed [15:0] accel_z,
    output reg  signed [15:0] gyro_x,
    output reg  signed [15:0] gyro_y,
    output reg         valid
);

    // MPU-6500 Registers
    localparam MPU_PWR_MGMT_1   = 8'h6B;
    localparam MPU_WHO_AM_I     = 8'h75;

    // Register Addresses for reading
    wire [7:0] REG_ADDRS [0:4];
    assign REG_ADDRS[0] = 8'h3B; // ACCEL_XOUT_H
    assign REG_ADDRS[1] = 8'h3D; // ACCEL_YOUT_H
    assign REG_ADDRS[2] = 8'h3F; // ACCEL_ZOUT_H
    assign REG_ADDRS[3] = 8'h43; // GYRO_XOUT_H
    assign REG_ADDRS[4] = 8'h45; // GYRO_YOUT_H

    // SPI Master Instance
    wire       spi_start;
    wire [7:0] spi_data_in;
    wire [7:0] spi_data_out;
    wire       spi_busy;
    wire       spi_done;

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

    // SPI Sub-modules
    reg         write_start;
    reg  [7:0]  write_addr;
    reg  [7:0]  write_data;
    wire        write_busy;
    wire        write_done;
    wire        write_spi_start;
    wire [7:0]  write_spi_data_in;
    wire        write_spi_cs_n;

    spi_write_reg spi_write_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(write_start),
        .reg_addr(write_addr),
        .reg_data(write_data),
        .busy(write_busy),
        .done(write_done),
        .spi_start(write_spi_start),
        .spi_data_in(write_spi_data_in),
        .spi_busy(spi_busy),
        .spi_done(spi_done),
        .spi_cs_n(write_spi_cs_n)
    );

    reg         read_start;
    reg  [7:0]  read_addr;
    wire [15:0] read_data;
    wire        read_busy;
    wire        read_done;
    wire        read_spi_start;
    wire [7:0]  read_spi_data_in;
    wire        read_spi_cs_n;

    spi_read_reg_16 spi_read_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(read_start),
        .reg_addr(read_addr),
        .reg_data(read_data),
        .busy(read_busy),
        .done(read_done),
        .spi_start(read_spi_start),
        .spi_data_in(read_spi_data_in),
        .spi_data_out(spi_data_out),
        .spi_busy(spi_busy),
        .spi_done(spi_done),
        .spi_cs_n(read_spi_cs_n)
    );


    // Muxing for spi_master inputs based on active sub-module
    // We assume write and read are never active simultaneously.
    wire active_write = write_busy || write_start;
    wire active_read  = read_busy || read_start;

    assign spi_start   = active_write ? write_spi_start   : (active_read ? read_spi_start   : 1'b0);
    assign spi_data_in = active_write ? write_spi_data_in : (active_read ? read_spi_data_in : 8'h00);
    assign spi_cs_n    = active_write ? write_spi_cs_n    : (active_read ? read_spi_cs_n    : 1'b1);

    // Main MPU States
    localparam S_INIT          = 0;
    localparam S_RST_1         = 1;
    localparam S_RST_1_WAIT    = 2;
    localparam S_RST_DELAY     = 3;
    localparam S_WAKE_1        = 4;
    localparam S_WAKE_1_WAIT   = 5;
    localparam S_WAKE_DELAY    = 6;
    localparam S_CHECK_WHOAMI  = 7;
    localparam S_CHECK_WAIT    = 8;
    localparam S_RETRY_DELAY   = 9;
    localparam S_IDLE          = 10;
    localparam S_READ_START    = 11;
    localparam S_READ_WAIT     = 12;
    localparam S_READ_DELAY    = 13;
    localparam S_UPDATE        = 14;

    reg [3:0]  state;
    reg [2:0]  read_idx;
    reg [20:0] timer;

    wire [20:0] delay_100ms = INIT_WAIT_100MS;
    wire [20:0] delay_200ms = INIT_WAIT_200MS;
    wire [20:0] delay_between_reads = 20;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_INIT;
            timer       <= 0;
            read_idx    <= 0;
            valid       <= 0;
            accel_x     <= 0;
            accel_y     <= 0;
            accel_z     <= 0;
            gyro_x      <= 0;
            gyro_y      <= 0;
            write_start <= 0;
            write_addr  <= 0;
            write_data  <= 0;
            read_start  <= 0;
            read_addr   <= 0;
        end else begin
            valid <= 0;
            write_start <= 0;
            read_start <= 0;

            case (state)
                S_INIT: begin
                    state <= S_RST_1;
                end

                S_RST_1: begin
                    // Write PWR_MGMT_1 (0x6B) to 0x80 (Reset)
                    write_addr  <= MPU_PWR_MGMT_1;
                    write_data  <= 8'h80;
                    write_start <= 1;
                    state       <= S_RST_1_WAIT;
                end

                S_RST_1_WAIT: begin
                    if (write_done) begin
                        timer <= 0;
                        state <= S_RST_DELAY;
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
                    write_addr  <= MPU_PWR_MGMT_1;
                    write_data  <= 8'h01;
                    write_start <= 1;
                    state       <= S_WAKE_1_WAIT;
                end

                S_WAKE_1_WAIT: begin
                    if (write_done) begin
                        timer <= 0;
                        state <= S_WAKE_DELAY;
                    end
                end

                S_WAKE_DELAY: begin
                    // Wait 200ms
                    if (timer >= delay_200ms) begin
                        state <= S_CHECK_WHOAMI;
                        timer <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_CHECK_WHOAMI: begin
                    read_addr  <= MPU_WHO_AM_I;
                    read_start <= 1;
                    state       <= S_CHECK_WAIT;
                end

                S_CHECK_WAIT: begin
                    if (read_done) begin
                        if (read_data[15:8] == 8'h70) begin
                            state <= S_IDLE;
                        end else begin
                            // Loop back to init if WHO_AM_I fails, but wait first
                            timer <= 0;
                            state <= S_RETRY_DELAY;
                        end
                    end
                end

                S_RETRY_DELAY: begin
                    if (timer >= delay_100ms) begin
                        state <= S_INIT;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_IDLE: begin
                    if (timer >= TIMER_LIMIT) begin
                        read_idx   <= 0;
                        state      <= S_READ_START;
                        timer      <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                S_READ_START: begin
                    read_addr  <= REG_ADDRS[read_idx];
                    read_start <= 1;
                    state      <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    if (read_done) begin
                        case (read_idx)
                            0: accel_x <= read_data;
                            1: accel_y <= read_data;
                            2: accel_z <= read_data;
                            3: gyro_x  <= read_data;
                            4: gyro_y  <= read_data;
                        endcase

                        if (read_idx == 4) begin
                            state <= S_UPDATE;
                        end else begin
                            read_idx <= read_idx + 1;
                            timer    <= 0;
                            state    <= S_READ_DELAY;

                        end
                    end
                end

                S_READ_DELAY: begin
                    if (timer >= delay_between_reads) begin
                        state <= S_READ_START;
                    end else begin
                        timer <= timer + 1;
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
