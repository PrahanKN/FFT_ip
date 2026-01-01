# FFT_ip


Configure the fft ip core clk freq,N points and the data width and type of data.

Use a clk sim or clk wizard,set clk freq match with fft block

Add the signal or testvectors module and add it is has blk ,set it to match transform length and wt type of data u send
connect tlast and tvalid signals

Add concat blk,connect the real and imag signed integers.Then connect concated output data to the fft ip blk

Add const blk and set its value to 1,and connect it to fft ip blk master tready 

Add 2slices to capture output real and imag parts,configure it 31:16imag 15:0real

To calculate abs value of fft,done by squaring real n imag values.To do this add multiplier and set inputs to 16bits and connect input of multiplier to imag part output of slice and do the same for real too

Then use adder blk and set its bit to 32,connect outputs of multipliers to adder input

Make mastertvalid,tlast, slave's tlast, adder's output, and output real part of signal or testvector module as external pin

Then create a hdl wrapper
