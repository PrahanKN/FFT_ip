// Normal Verilog translation of the provided VHDL complex_signal_generator
// Notes:
//  - FFT_Size and FUNC_TYPE are parameters.
//  - reset is active-low to match the VHDL behavior (reset = '0' means reset).
//  - LUTs are initialized in an initial block (elaboration time).
//  - Uses real arithmetic in the initial block to compute LUT contents.
//  - Outputs are 16-bit signed two's complement values.

module complex_signal_generator #(
    parameter integer FFT_Size = 1024,
    parameter integer FUNC_TYPE = 0  // 0: exp(j*theta), 1: sinc, 2: rectangular
)(
    input  wire             clk,
    input  wire             reset,       // active low (reset = 0 -> reset asserted)
    output wire [15:0]      real_out,
    output wire [15:0]      imagery_out,
    output reg              tvalid,
    output reg              tlast
);

    // Local constants for math
    real PI = 3.141592653589793;
    real SCALE = 32767.0;

    // LUTs: signed 16-bit values
    reg signed [15:0] cos_LUT   [0:FFT_Size-1];
    reg signed [15:0] sin_LUT   [0:FFT_Size-1];
    reg signed [15:0] sinc_LUT  [0:FFT_Size-1];
    reg signed [15:0] rect_LUT  [0:FFT_Size-1];

    // runtime signals
    integer i;
    integer center;
    integer theta_index;
    reg signed [15:0] real_temp;
    reg signed [15:0] imag_temp;

    // Initialize LUTs at elaboration time
    initial begin
        center = FFT_Size / 2;
        for (i = 0; i < FFT_Size; i = i + 1) begin
            real angle;
            real cosv;
            real sinv;
            real x;
            real sinc_val;
            integer rounded;

            // compute angle similar to VHDL: angle := (8*2.0 * MATH_PI * real(i)) / real(FFT_Size);
            angle = (8.0 * 2.0 * PI * i) / FFT_Size;

            // cos LUT
            cosv = SCALE * $cos(angle);
            // simple rounding: floor(x+0.5) (note: negative values may be rounded toward -inf)
            rounded = $rtoi($floor(cosv + 0.5));
            if (rounded > 32767) rounded = 32767;
            if (rounded < -32768) rounded = -32768;
            cos_LUT[i] = rounded;

            // sin LUT
            sinv = SCALE * $sin(angle);
            rounded = $rtoi($floor(sinv + 0.5));
            if (rounded > 32767) rounded = 32767;
            if (rounded < -32768) rounded = -32768;
            sin_LUT[i] = rounded;

            // sinc LUT: VHDL used (angle-4.0*2.0*3.14) as shift; replicate that
            x = angle - (4.0 * 2.0 * 3.14);
            if (i == 0) begin
                sinc_LUT[i] = 0;
            end else begin
                if (x == 0.0) begin
                    sinc_val = 0.0;
                end else begin
                    sinc_val = SCALE * ($sin(x) / x);
                end
                rounded = $rtoi($floor(sinc_val + 0.5));
                if (rounded > 32767) rounded = 32767;
                if (rounded < -32768) rounded = -32768;
                sinc_LUT[i] = rounded;
            end

            // rectangular window around center +/- 2 (VHDL used > center-3 and < center+3)
            if ((i > (center - 3)) && (i < (center + 3))) begin
                rect_LUT[i] = 16'sd32767;
            end else begin
                rect_LUT[i] = 16'sd0;
            end
        end
    end

    // Sequential logic: index increment, tvalid/tlast, and select outputs based on FUNC_TYPE
    initial begin
        theta_index = 0;
        real_temp = 16'sd0;
        imag_temp = 16'sd0;
        tvalid = 1'b0;
        tlast  = 1'b0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            // active-low reset asserted
            theta_index <= 0;
            real_temp   <= 16'sd0;
            imag_temp   <= 16'sd0;
            tvalid      <= 1'b0;
            tlast       <= 1'b0;
        end else begin
            // increment index with wrap
            if (theta_index == (FFT_Size - 1))
                theta_index <= 0;
            else
                theta_index <= theta_index + 1;

            tvalid <= 1'b1; // always valid when not in reset

            // tlast asserted when current index is last sample (use previous index value semantics
            // similar to VHDL: check theta_index before increment; here we check the next state:
            if (theta_index == (FFT_Size - 1))
                tlast <= 1'b1;
            else
                tlast <= 1'b0;

            // Select function type (FUNC_TYPE is a parameter)
            case (FUNC_TYPE)
                0: begin
                    real_temp <= cos_LUT[theta_index];
                    imag_temp <= sin_LUT[theta_index];
                end
                1: begin
                    real_temp <= sinc_LUT[theta_index];
                    imag_temp <= sinc_LUT[theta_index];
                end
                2: begin
                    real_temp <= rect_LUT[theta_index];
                    imag_temp <= rect_LUT[theta_index];
                end
                default: begin
                    real_temp <= 16'sd0;
                    imag_temp <= 16'sd0;
                end
            endcase
        end
    end

    // Output assignments (two's complement 16-bit)
    assign real_out    = real_temp;
    assign imagery_out = imag_temp;

endmodule

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity complex_signal_generator is
    generic (
        FFT_Size : integer := 1024;
        FUNC_TYPE : integer := 0  -- 0: exp(j*theta), 1: sinc, 2: rectangular
    );
    port (
        clk          : in  STD_LOGIC;
        reset        : in  STD_LOGIC;
        real_out     : out STD_LOGIC_VECTOR(15 downto 0);
        imagery_out  : out STD_LOGIC_VECTOR(15 downto 0);
        tvalid       : out STD_LOGIC;
        tlast        : out STD_LOGIC
    );
end entity complex_signal_generator;

architecture Behavioral of complex_signal_generator is
    type LUT_TYPE is array (0 to FFT_Size-1) of integer range -32768 to 32767;
    signal cos_LUT, sin_LUT, sinc_LUT, rect_LUT : LUT_TYPE;
    signal theta_index      : integer range 0 to FFT_Size-1 := 0;
    signal real_temp, imag_temp : integer range -32768 to 32767;

begin
    -- Generate LUT values at elaboration time
    process
        variable angle : real;
        variable center : integer := FFT_Size / 2;
    begin
        for i in 0 to FFT_Size-1 loop
            angle := (8*2.0 * MATH_PI * real(i)) / real(FFT_Size);
            cos_LUT(i) <= integer(round(32767.0 * cos(angle)));
            sin_LUT(i) <= integer(round(32767.0 * sin(angle)));
            
            if i = 0 then
                sinc_LUT(i) <= 0;
            else
                sinc_LUT(i) <= integer(round(32767.0 * sin(angle-4.0*2.0*3.14) / (angle-4.0*2.0*3.14)));
            end if;
            
            if i > (FFT_Size / 2)-3 and  i < (FFT_Size / 2)+3 then
                rect_LUT(i) <= 32767;
            else
                rect_LUT(i) <= 0;
            end if;
        end loop;
        wait;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                theta_index <= 0;
                real_temp <= 0;
                imag_temp <= 0;
                tvalid <= '0';
                tlast <= '0';
            else
                theta_index <= (theta_index + 1) mod FFT_Size;
                tvalid <= '1'; -- Always valid unless reset
                
                if theta_index = FFT_Size - 1 then
                    tlast <= '1'; -- Assert tlast on the last sample
                else
                    tlast <= '0';
                end if;
                
                case FUNC_TYPE is
                    when 0 =>
                        real_temp <= cos_LUT(theta_index);
                        imag_temp <= sin_LUT(theta_index);
                    when 1 =>
                        real_temp <= sinc_LUT(theta_index);
                        imag_temp <= sinc_LUT(theta_index);
                    when 2 =>
                        real_temp <= rect_LUT(theta_index);
                        imag_temp <= rect_LUT(theta_index);
                    when others =>
                        real_temp <= 0;
                        imag_temp <= 0;
                end case;
            end if;
        end if;
    end process;

    real_out <= std_logic_vector(to_signed(real_temp, 16));
    imagery_out <= std_logic_vector(to_signed(imag_temp, 16));

end Behavioral;
