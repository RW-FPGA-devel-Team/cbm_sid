-------------------------------------------------------------------------------
--
--                                 SID 6581
--
--     A fully functional SID chip implementation in VHDL
--
-------------------------------------------------------------------------------
--	to do:	- filter
--				- smaller implementation, use multiplexed channels
--
--
-- "The Filter was a classic multi-mode (state variable) VCF design. There was
-- no way to create a variable transconductance amplifier in our NMOS process,
-- so I simply used FETs as voltage-controlled resistors to control the cutoff
-- frequency. An 11-bit D/A converter generates the control voltage for the
-- FETs (it's actually a 12-bit D/A, but the LSB had no audible affect so I
-- disconnected it!)."
-- "Filter resonance was controlled by a 4-bit weighted resistor ladder. Each
-- bit would turn on one of the weighted resistors and allow a portion of the
-- output to feed back to the input. The state-variable design provided
-- simultaneous low-pass, band-pass and high-pass outputs. Analog switches
-- selected which combination of outputs were sent to the final amplifier (a
-- notch filter was created by enabling both the high and low-pass outputs
-- simultaneously)."
-- "The filter is the worst part of SID because I could not create high-gain
-- op-amps in NMOS, which were essential to a resonant filter. In addition,
-- the resistance of the FETs varied considerably with processing, so different
-- lots of SID chips had different cutoff frequency characteristics. I knew it
-- wouldn't work very well, but it was better than nothing and I didn't have
-- time to make it better."
--
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

-------------------------------------------------------------------------------

entity sid8580 is
	port (
		clk_1MHz			: in std_logic;		-- main SID clock signal
		clk32				: in std_logic;		-- main clock signal
		reset				: in std_logic;		-- high active signal (reset when reset = '1')
		cs					: in std_logic;		-- "chip select", when this signal is '1' this model can be accessed
		we					: in std_logic;		-- when '1' this model can be written to, otherwise access is considered as read

		addr				: in unsigned(4 downto 0);	-- address lines
		din				: in unsigned(7 downto 0);	-- data in (to chip)
		dout				: out unsigned(7 downto 0);	-- data out	(from chip)

		pot_x				: in unsigned(7 downto 0);	-- paddle input-X
		pot_y				: in unsigned(7 downto 0);	-- paddle input-Y
 
		audio_8580		: out unsigned(17 downto 0)

	);
end sid8580;

architecture Behavioral of sid8580 is

	signal Voice_1_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_1_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Osc		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Env		: unsigned(7 downto 0)	:= (others => '0');

	signal Voice_2_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_2_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Osc		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Env		: unsigned(7 downto 0)	:= (others => '0');

	signal Voice_3_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_3_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');

	signal Filter_Fc_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Fc_hi		: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Res_Filt	: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Mode_Vol	: unsigned(7 downto 0)	:= (others => '0');

	signal Misc_PotX			: unsigned(7 downto 0)	:= (others => '0');
	signal Misc_PotY			: unsigned(7 downto 0)	:= (others => '0');
	signal Misc_Osc3_Random	: unsigned(7 downto 0)	:= (others => '0');
	signal Misc_8580_Env3	: unsigned(7 downto 0)	:= (others => '0');

	signal do_buf				: unsigned(7 downto 0)	:= (others => '0');
   signal last_wr				: unsigned(7 downto 0)	:= (others => '0');

	signal voice_8580_1				: unsigned(11 downto 0)	:= (others => '0');
	signal voice_8580_2				: unsigned(11 downto 0)	:= (others => '0');
	signal voice_8580_3				: unsigned(11 downto 0)	:= (others => '0');

   signal voice_1_PA_MSB_8580	: std_logic := '0';
	signal voice_2_PA_MSB_8580	: std_logic := '0';
	signal voice_3_PA_MSB_8580	: std_logic := '0';

	signal v8580_1_signed		: signed(12 downto 0);
	signal v8580_2_signed		: signed(12 downto 0);
	signal v8580_3_signed		: signed(12 downto 0);
	
	constant ext_in_signed	: signed(12 downto 0) := to_signed(0,13);

	signal filtered_8580	: signed(18 downto 0);
	signal tick_q1, tick_q2	: std_logic;
	signal input_valid		: std_logic;
	signal u_audio_8580  	: unsigned(17 downto 0);
	signal u_filt_8580		: unsigned(18 downto 0);
	signal ff1					: std_logic;
	
   signal sawtooth_1			: unsigned(11 downto 0);
	signal triangle_1			: unsigned(11 downto 0);
   signal sawtooth_2			: unsigned(11 downto 0);
	signal triangle_2			: unsigned(11 downto 0);
   signal sawtooth_3			: unsigned(11 downto 0);
	signal triangle_3			: unsigned(11 downto 0);

   signal f_sawtooth 			: unsigned(11 downto 0);
	signal f_triangle 			: unsigned(11 downto 0);

 	signal w_st_out_1 		: unsigned(7 downto 0);
	signal w_p_t_out_1  		: unsigned(7 downto 0);
	signal w_ps_out_1 		: unsigned(7 downto 0);
	signal w_pst_out_1  		: unsigned(7 downto 0);

  	signal w_st_out_2  		: unsigned(7 downto 0);
	signal w_p_t_out_2  		: unsigned(7 downto 0);
	signal w_ps_out_2  		: unsigned(7 downto 0);
	signal w_pst_out_2  		: unsigned(7 downto 0);

  	signal w_st_out_3  		: unsigned(7 downto 0);
	signal w_p_t_out_3  		: unsigned(7 downto 0);
	signal w_ps_out_3  		: unsigned(7 downto 0);
	signal w_pst_out_3  		: unsigned(7 downto 0);

 	signal f_st_out  			: unsigned(7 downto 0);
	signal f_p_t_out  		: unsigned(7 downto 0);
	signal f_ps_out  			: unsigned(7 downto 0);
	signal f_pst_out  		: unsigned(7 downto 0);

	signal t_state : integer range 0 to 16; -- stage counter 0-16;
	
	
	component sid_tables
	port (
		clock    : in std_logic;
		sawtooth : in unsigned(11 downto 0);
		triangle : in unsigned(11 downto 0);
		w_st_out : out unsigned(7 downto 0);
		w_p_t_out: out unsigned(7 downto 0);
		w_ps_out : out unsigned(7 downto 0);
		w_pst_out: out unsigned(7 downto 0)
		
	);
	end component sid_tables;
	
-------------------------------------------------------------------------------

begin

------------------------ SID 8580 voices --------------------------------------

	tablas : sid_tables
	port map (
	   clock    => clk_1MHz,
		sawtooth => f_sawtooth,
		triangle => f_triangle,
		w_st_out  => f_st_out,
		w_p_t_out => f_p_t_out,
		w_ps_out  => f_ps_out,
		w_pst_out => f_pst_out
	);


	v_8580_1: entity work.sid_voice_8580
	port map(
	   clk32             => clk32,
		clk_1MHz				=> clk_1MHz,
		reset					=> reset,
		Freq_lo				=> Voice_1_Freq_lo,
		Freq_hi				=> Voice_1_Freq_hi,
		Pw_lo					=> Voice_1_Pw_lo,
		Pw_hi					=> Voice_1_Pw_hi,
		Control				=> Voice_1_Control,
		Att_dec				=> Voice_1_Att_dec,
		Sus_Rel				=> Voice_1_Sus_Rel,
		PA_MSB_in			=> voice_3_PA_MSB_8580,
		PA_MSB_out			=> voice_1_PA_MSB_8580,
		Osc					=> Voice_1_Osc,
		Env					=> Voice_1_Env,

		sawtooth 			=> sawtooth_1,
		triangle 			=> triangle_1,
		w_st_out 			=> w_st_out_1,
		w_p_t_out 			=> w_p_t_out_1,
		w_ps_out  			=> w_ps_out_1,
		w_pst_out 			=> w_pst_out_1,
	
		voice					=> voice_8580_1
	);

	v_8580_2: entity work.sid_voice_8580
	port map(
	   clk32             => clk32,
	   clk_1MHz				=> clk_1MHz,
		reset					=> reset,
		Freq_lo				=> Voice_2_Freq_lo,
		Freq_hi				=> Voice_2_Freq_hi,
		Pw_lo					=> Voice_2_Pw_lo,
		Pw_hi					=> Voice_2_Pw_hi,
		Control				=> Voice_2_Control,
		Att_dec				=> Voice_2_Att_dec,
		Sus_Rel				=> Voice_2_Sus_Rel,
		PA_MSB_in			=> voice_1_PA_MSB_8580,
		PA_MSB_out			=> voice_2_PA_MSB_8580,
		Osc					=> Voice_2_Osc,
		Env					=> Voice_2_Env,
		
		sawtooth 			=> sawtooth_2,
		triangle 			=> triangle_2,
		w_st_out 			=> w_st_out_2,
		w_p_t_out 			=> w_p_t_out_2,
		w_ps_out  			=> w_ps_out_2,
		w_pst_out 			=> w_pst_out_2,

		voice					=> voice_8580_2
	);

	v_8580_3: entity work.sid_voice_8580
	port map(
		clk_1MHz				=> clk_1MHz,
		clk32             => clk32,
		reset					=> reset,
		Freq_lo				=> Voice_3_Freq_lo,
		Freq_hi				=> Voice_3_Freq_hi,
		Pw_lo					=> Voice_3_Pw_lo,
		Pw_hi					=> Voice_3_Pw_hi,
		Control				=> Voice_3_Control,
		Att_dec				=> Voice_3_Att_dec,
		Sus_Rel				=> Voice_3_Sus_Rel,
		PA_MSB_in			=> voice_2_PA_MSB_8580,
		PA_MSB_out			=> voice_3_PA_MSB_8580,
		Osc					=> Misc_Osc3_Random,
		Env					=> Misc_8580_Env3,
		
		sawtooth 			=> sawtooth_3,
		triangle 			=> triangle_3,
		w_st_out 			=> w_st_out_3,
		w_p_t_out 			=> w_p_t_out_3,
		w_ps_out  			=> w_ps_out_3,
		w_pst_out 			=> w_pst_out_3,

		voice					=> voice_8580_3
	);

-------------------------------------------------------------------------------------
	dout						<= unsigned(do_buf);

-- SID filters

	process (clk_1MHz,reset)
	begin
		if reset='1' then
			ff1<='0';
		else
			if rising_edge(clk_1MHz) then
				ff1<=not ff1;
			end if;
		end if;
	end process;

	process(clk32)
	begin
		if rising_edge(clk32) then
			tick_q1 <= ff1;
			tick_q2 <= tick_q1;
		end if;
	end process;

	process (clk_1MHz)
	begin
	 
	 if falling_edge(clk_1MHz) then
	   t_state <= 0;
	 end if;
	 t_state<=t_state+1;
	 
	 case t_state is
		when 1 => f_sawtooth <= sawtooth_1;
					 f_triangle <= triangle_1;
		when 5 => f_sawtooth <= sawtooth_2;
					 f_triangle <= triangle_2;
  		when 9 => f_sawtooth <= sawtooth_3;
					 f_triangle <= triangle_3;
		when 3 => w_st_out_1 <= f_st_out;
		          w_p_t_out_1 <= f_p_t_out;
		          w_ps_out_1  <= f_ps_out;
		          w_pst_out_1 <= f_pst_out;
		when 7 => w_st_out_2 <= f_st_out;
		          w_p_t_out_2 <= f_p_t_out;
		          w_ps_out_2  <= f_ps_out;
		          w_pst_out_2 <= f_pst_out;
		when 11 => w_st_out_3 <= f_st_out;
		          w_p_t_out_3 <= f_p_t_out;
		          w_ps_out_3  <= f_ps_out;
		          w_pst_out_3 <= f_pst_out;
							 
	   when others => null;
	 end case; 
   		
	  
	end process;
	
	input_valid <= '1' when tick_q1 /=tick_q2 else '0';

	v8580_1_signed <= signed('0' & voice_8580_1); -- - 2048;
	v8580_2_signed <= signed('0' & voice_8580_2); -- - 2048;
	v8580_3_signed <= signed('0' & voice_8580_3); -- - 2048;


---------------------------------------------------------------
--- 8580 filter section
---------------------------------------------------------------
	
	filters_8580: entity work.sid_filters_8580
	port map (
		clk			=> clk32,
		rst			=> reset,
		-- SID registers.
		Fc_lo			=> Filter_Fc_lo,
		Fc_hi			=> Filter_Fc_hi,
		Res_Filt		=> Filter_Res_Filt,
		Mode_Vol		=> Filter_Mode_Vol,
		-- Voices - resampled to 13 bit
		voice1		=> v8580_1_signed,
		voice2		=> v8580_2_signed,
		voice3		=> v8580_3_signed,
		--
		input_valid => input_valid,
		ext_in		=> ext_in_signed,

		sound			=> filtered_8580,
		valid			=> open
	);
	
	u_filt_8580 	<= unsigned(filtered_8580 + "1000000000000000000");
	u_audio_8580	<= u_filt_8580(18 downto 1);
	--audio_8580		<= voice_8580_3 & "000000"; --u_audio_8580;
	audio_8580		<= u_audio_8580;
--------------------------------------------------------------------------------
-- Register decoding
--------------------------------------------------------------------------------
	register_decoder:process(clk32)
	begin
		if rising_edge(clk32) then
			if (reset = '1') then
				--------------------------------------- Voice-1
				Voice_1_Freq_lo	<= (others => '0');
				Voice_1_Freq_hi	<= (others => '0');
				Voice_1_Pw_lo		<= (others => '0');
				Voice_1_Pw_hi		<= (others => '0');
				Voice_1_Control	<= (others => '0');
				Voice_1_Att_dec	<= (others => '0');
				Voice_1_Sus_Rel	<= (others => '0');
				--------------------------------------- Voice-2
				Voice_2_Freq_lo	<= (others => '0');
				Voice_2_Freq_hi	<= (others => '0');
				Voice_2_Pw_lo		<= (others => '0');
				Voice_2_Pw_hi		<= (others => '0');
				Voice_2_Control	<= (others => '0');
				Voice_2_Att_dec	<= (others => '0');
				Voice_2_Sus_Rel	<= (others => '0');
				--------------------------------------- Voice-3
				Voice_3_Freq_lo	<= (others => '0');
				Voice_3_Freq_hi	<= (others => '0');
				Voice_3_Pw_lo		<= (others => '0');
				Voice_3_Pw_hi		<= (others => '0');
				Voice_3_Control	<= (others => '0');
				Voice_3_Att_dec	<= (others => '0');
				Voice_3_Sus_Rel	<= (others => '0');
				--------------------------------------- Filter & volume
				Filter_Fc_lo		<= (others => '0');
				Filter_Fc_hi		<= (others => '0');
				Filter_Res_Filt	<= (others => '0');
				Filter_Mode_Vol	<= (others => '0');
			else
				Voice_1_Freq_lo	<= Voice_1_Freq_lo;
				Voice_1_Freq_hi	<= Voice_1_Freq_hi;
				Voice_1_Pw_lo		<= Voice_1_Pw_lo;
				Voice_1_Pw_hi		<= Voice_1_Pw_hi;
				Voice_1_Control	<= Voice_1_Control;
				Voice_1_Att_dec	<= Voice_1_Att_dec;
				Voice_1_Sus_Rel	<= Voice_1_Sus_Rel;
				Voice_2_Freq_lo	<= Voice_2_Freq_lo;
				Voice_2_Freq_hi	<= Voice_2_Freq_hi;
				Voice_2_Pw_lo		<= Voice_2_Pw_lo;
				Voice_2_Pw_hi		<= Voice_2_Pw_hi;
				Voice_2_Control	<= Voice_2_Control;
				Voice_2_Att_dec	<= Voice_2_Att_dec;
				Voice_2_Sus_Rel	<= Voice_2_Sus_Rel;
				Voice_3_Freq_lo	<= Voice_3_Freq_lo;
				Voice_3_Freq_hi	<= Voice_3_Freq_hi;
				Voice_3_Pw_lo		<= Voice_3_Pw_lo;
				Voice_3_Pw_hi		<= Voice_3_Pw_hi;
				Voice_3_Control	<= Voice_3_Control;
				Voice_3_Att_dec	<= Voice_3_Att_dec;
				Voice_3_Sus_Rel	<= Voice_3_Sus_Rel;
				Filter_Fc_lo		<= Filter_Fc_lo;
				Filter_Fc_hi		<= Filter_Fc_hi;
				Filter_Res_Filt	<= Filter_Res_Filt;
				Filter_Mode_Vol	<= Filter_Mode_Vol;
				do_buf 				<= (others => '0');

				if (cs='1') then
					if (we='1') then	-- Write to SID-register
					last_wr <= din;
								------------------------
						case addr is
							-------------------------------------- Voice-1	
							when "00000" =>	Voice_1_Freq_lo	<= din;
							when "00001" =>	Voice_1_Freq_hi	<= din;
							when "00010" =>	Voice_1_Pw_lo		<= din;
							when "00011" =>	Voice_1_Pw_hi		<= din(3 downto 0);
							when "00100" =>	Voice_1_Control	<= din;
							when "00101" =>	Voice_1_Att_dec	<= din;
							when "00110" =>	Voice_1_Sus_Rel	<= din;
							--------------------------------------- Voice-2
							when "00111" =>	Voice_2_Freq_lo	<= din;
							when "01000" =>	Voice_2_Freq_hi	<= din;
							when "01001" =>	Voice_2_Pw_lo		<= din;
							when "01010" =>	Voice_2_Pw_hi		<= din(3 downto 0);
							when "01011" =>	Voice_2_Control	<= din;
							when "01100" =>	Voice_2_Att_dec	<= din;
							when "01101" =>	Voice_2_Sus_Rel	<= din;
							--------------------------------------- Voice-3
							when "01110" =>	Voice_3_Freq_lo	<= din;
							when "01111" =>	Voice_3_Freq_hi	<= din;
							when "10000" =>	Voice_3_Pw_lo		<= din;
							when "10001" =>	Voice_3_Pw_hi		<= din(3 downto 0);
							when "10010" =>	Voice_3_Control	<= din;
							when "10011" =>	Voice_3_Att_dec	<= din;
							when "10100" =>	Voice_3_Sus_Rel	<= din;
							--------------------------------------- Filter & volume
							when "10101" =>	Filter_Fc_lo		<= din;
							when "10110" =>	Filter_Fc_hi		<= din;
							when "10111" =>	Filter_Res_Filt	<= din;
							when "11000" =>	Filter_Mode_Vol	<= din;
							--------------------------------------
							when others	=>	null;
						end case;

					else			-- Read from SID-register
							-------------------------
						--case CONV_INTEGER(addr) is
						case addr is
							-------------------------------------- Misc
							when "11001" =>	do_buf	<= pot_x;
							when "11010" =>	do_buf	<= pot_y;
							when "11011" =>	do_buf	<= Misc_Osc3_Random;
							when "11100" =>	do_buf	<= Misc_8580_Env3;   -- TODO
							--------------------------------------
							when others	=>	do_buf <= last_wr;
						end case;		
					end if;
				end if;
			end if;
		end if;
	end process;

end Behavioral;
