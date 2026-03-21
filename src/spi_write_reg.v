`default_nettype none

module spi_write_reg (
    input  wire       clk,
    input  wire       rst_n,

    // Interface to parent
    input  wire       start,
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,
    output reg        busy,
    output reg        done,

    // Interface to spi_master
    output reg        spi_start,
    output reg  [7:0] spi_data_in,
    input  wire       spi_busy,
    input  wire       spi_done,
    output reg        spi_cs_n
);

    localparam S_IDLE       = 0;
    localparam S_SEND_ADDR  = 1;
    localparam S_WAIT_ADDR  = 2;
    localparam S_SEND_DATA  = 3;
    localparam S_WAIT_DATA  = 4;

    reg [2:0] state;
    reg [7:0] stored_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 0;
            done        <= 0;
            spi_start   <= 0;
            spi_data_in <= 0;
            spi_cs_n    <= 1;
            stored_data <= 0;
        end else begin
            done      <= 0;
            spi_start <= 0;

            case (state)
                S_IDLE: begin
                    spi_cs_n <= 1;
                    if (start) begin
                        busy        <= 1;
                        stored_data <= reg_data;
                        spi_cs_n    <= 0;
                        spi_data_in <= reg_addr; // Write (MSB 0)
                        spi_start   <= 1;
                        state       <= S_WAIT_ADDR;
                    end else begin
                        busy <= 0;
                    end
                end

                S_WAIT_ADDR: begin
                    if (spi_done) begin
                        spi_data_in <= stored_data;
                        spi_start   <= 1;
                        state       <= S_WAIT_DATA;
                    end
                end

                S_WAIT_DATA: begin
                    if (spi_done) begin
                        spi_cs_n <= 1;
                        done     <= 1;
                        busy     <= 0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
