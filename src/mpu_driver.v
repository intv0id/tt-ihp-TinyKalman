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

    // SPI Master Instance

    wire       spi_tx_ready;
    wire [1:0] spi_rx_count;
    wire       spi_rx_dv;
    wire [7:0] spi_rx_byte;

    reg  [1:0] spi_tx_count;
    reg  [7:0] spi_tx_byte;
    reg        spi_tx_dv;

    SPI_Master_With_Single_CS #(
        .SPI_MODE(3),
        .CLKS_PER_HALF_BIT(CLK_DIV),
        .MAX_BYTES_PER_CS(3),
        .CS_INACTIVE_CLKS(10)
    ) spi_master_inst (
        .i_Rst_L(rst_n),
        .i_Clk(clk),
        .i_TX_Count(spi_tx_count),
        .i_TX_Byte(spi_tx_byte),
        .i_TX_DV(spi_tx_dv),
        .o_TX_Ready(spi_tx_ready),
        .o_RX_Count(spi_rx_count),
        .o_RX_DV(spi_rx_dv),
        .o_RX_Byte(spi_rx_byte),
        .o_SPI_Clk(spi_sclk),
        .i_SPI_MISO(spi_miso),
        .o_SPI_MOSI(spi_mosi),
        .o_SPI_CS_n(spi_cs_n)
    );

    // SPI Interface State Machine
    localparam SPI_IDLE       = 0;
    localparam SPI_WAIT_TX1   = 1;
    localparam SPI_WAIT_TX2   = 2;
    localparam SPI_WAIT_TX3   = 3;

    reg [1:0] spi_fsm_state;

    reg         write_start;
    reg  [7:0]  write_addr;
    reg  [7:0]  write_data;
    reg         write_done;

    reg         read_start;
    reg  [7:0]  read_addr;
    reg  [15:0] read_data;
    reg         read_done;

    reg         read8_start;
    reg  [7:0]  read8_addr;
    reg  [7:0]  read8_data;
    reg         read8_done;

    reg [1:0] spi_op; // 0: none, 1: write, 2: read8, 3: read16

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_fsm_state <= SPI_IDLE;
            spi_tx_count  <= 0;
            spi_tx_byte   <= 0;
            spi_tx_dv     <= 0;
            write_done    <= 0;
            read_done     <= 0;
            read8_done    <= 0;
            read8_data    <= 0;
            read_data     <= 0;
            spi_op        <= 0;
        end else begin
            write_done <= 0;
            read_done  <= 0;
            read8_done <= 0;
            spi_tx_dv  <= 0;

            // Continously capture rx bytes to ensure we don't miss any if timing is tight
            if (spi_op == 2 && spi_rx_dv && spi_rx_count == 1) begin
                read8_data <= spi_rx_byte;
            end
            if (spi_op == 3 && spi_rx_dv) begin
                if (spi_rx_count == 1) read_data[15:8] <= spi_rx_byte;
                if (spi_rx_count == 2) read_data[7:0]  <= spi_rx_byte;
            end

            case (spi_fsm_state)
                SPI_IDLE: begin
                    if (write_start) begin
                        spi_tx_count  <= 2;
                        spi_tx_byte   <= write_addr;
                        spi_tx_dv     <= 1;
                        spi_op        <= 1;
                        spi_fsm_state <= SPI_WAIT_TX1;
                    end else if (read8_start) begin
                        spi_tx_count  <= 2;
                        spi_tx_byte   <= read8_addr | 8'h80; // Set MSB for read
                        spi_tx_dv     <= 1;
                        spi_op        <= 2;
                        spi_fsm_state <= SPI_WAIT_TX1;
                    end else if (read_start) begin
                        spi_tx_count  <= 3;
                        spi_tx_byte   <= read_addr | 8'h80; // Set MSB for read
                        spi_tx_dv     <= 1;
                        spi_op        <= 3;
                        spi_fsm_state <= SPI_WAIT_TX1;
                    end
                end

                SPI_WAIT_TX1: begin
                    if (spi_tx_ready) begin
                        if (spi_op == 1) begin
                            spi_tx_byte   <= write_data;
                        end else begin
                            spi_tx_byte   <= 8'h00; // Dummy byte
                        end
                        spi_tx_dv     <= 1;
                        spi_fsm_state <= SPI_WAIT_TX2;
                    end
                end

                SPI_WAIT_TX2: begin
                    if (spi_tx_ready) begin
                        if (spi_op == 3) begin
                            // 16-bit read needs one more byte
                            spi_tx_byte   <= 8'h00; // Dummy byte
                            spi_tx_dv     <= 1;
                            spi_fsm_state <= SPI_WAIT_TX3;
                        end else begin
                            // 8-bit read or write is done
                            if (spi_op == 1) write_done <= 1;
                            if (spi_op == 2) read8_done <= 1;
                            spi_op        <= 0;
                            spi_fsm_state <= SPI_IDLE;
                        end
                    end
                end

                SPI_WAIT_TX3: begin
                    if (spi_tx_ready) begin
                        read_done     <= 1;
                        spi_op        <= 0;
                        spi_fsm_state <= SPI_IDLE;
                    end
                end
            endcase
        end
    end

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
    reg [31:0] timer;

`ifdef FAST_SIM
    wire [31:0] delay_100ms = 10;
    wire [31:0] delay_200ms = 20;
    wire [31:0] delay_between_reads = 20;
`else
    wire [31:0] delay_100ms = INIT_WAIT_100MS;
    wire [31:0] delay_200ms = INIT_WAIT_200MS;
    wire [31:0] delay_between_reads = 20;
`endif

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
            gyro_z      <= 0;
            write_start <= 0;
            write_addr  <= 0;
            write_data  <= 0;
            read_start  <= 0;
            read_addr   <= 0;
            read8_start <= 0;
            read8_addr  <= 0;
        end else begin
            valid <= 0;
            write_start <= 0;
            read_start <= 0;
            read8_start <= 0;

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
                    read8_addr  <= MPU_WHO_AM_I;
                    read8_start <= 1;
                    state       <= S_CHECK_WAIT;
                end

                S_CHECK_WAIT: begin
                    if (read8_done) begin
                        if (read8_data == 8'h70) begin
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
                            5: gyro_z  <= read_data;
                        endcase

                        if (read_idx == 5) begin
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
