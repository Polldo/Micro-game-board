library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_tester is
	port    
	(
		clock				: in std_logic;
		reset 				: in std_logic;
		-- Read port
		read_req			: out std_logic;
		read_address		: out std_logic_vector(23 downto 0);
		read_length			: out std_logic_vector(8 downto 0);
		read_data			: in std_logic_vector(15 downto 0);
		read_ready			: in std_logic;
		read_data_valid		: in std_logic;
		-- Write port
		write_req			: out std_logic;
		write_address		: out std_logic_vector(23 downto 0);
		write_data			: out std_logic_vector(15 downto 0);
		write_ready			: in std_logic;
		write_done			: in std_logic;
		-- Test port
		button_in			: in std_logic;
		led_out				: out std_logic_vector(2 downto 0)
	);
end entity;

architecture sdram_testbench of memory_tester is
	signal address : std_logic_vector(23 downto 0);
	type state_type is (WRITE_STATE, WRITE_WAIT_STATE, WAIT_STATE, READ_STATE, READ_WAIT_STATE, PRINT_STATE, DEBOUNCE_STATE, DEBOUNCE_STATE_2);
	signal state_reg, state_next : state_type := WAIT_STATE;--WRITE_STATE;
	signal write_issued_reg, write_issued_next 		: std_logic := '0';
	signal data_received_reg, data_received_next 	: std_logic_vector(15 downto 0) := (others => '1');

	signal write_data_reg, write_data_next : std_logic_vector(15 downto 0) := (others => '0');
	signal write_address_reg, write_address_next : std_logic_vector(23 downto 0) := (others => '0');
	signal write_counter_reg, write_counter_next : unsigned(3 downto 0) := to_unsigned(0, 4);

	type buffer_type is array (15 downto 0) of std_logic_vector(15 downto 0);
	signal buffer_reg, buffer_next : buffer_type := (others => (others => '0'));
	signal read_address_reg, read_address_next : std_logic_vector(23 downto 0) := (others => '0');
	signal read_req_count_reg, read_req_count_next : unsigned(3 downto 0) := to_unsigned(0, 4);
	signal read_save_count_reg, read_save_count_next : unsigned(3 downto 0) := to_unsigned(0, 4);
	signal read_length_const : std_logic_vector(8 downto 0) := std_logic_vector(to_unsigned(7, 9));

	signal print_counter_reg, print_counter_next : unsigned(3 downto 0) := to_unsigned(0, 4); 

	signal debounce_counter_reg, debounce_counter_next : unsigned(31 downto 0) := to_unsigned(0, 32); 
begin

	led_out <= not data_received_reg(2 downto 0);

	process(clock, reset)
	begin
		if (reset = '1') then
			--state_reg 			<= WRITE_STATE;
			state_reg 			<= WAIT_STATE;
			write_issued_reg 	<= '0';
			data_received_reg	<= (others => '1');
			buffer_reg			<= (others => (others => '0'));
			write_data_reg 		<= (others => '0');
			write_address_reg	<= (others => '0');
			write_counter_reg	<= to_unsigned(0, write_counter_reg'length);
			read_address_reg	<= (others => '0');
			read_req_count_reg	<= to_unsigned(0, read_req_count_reg'length);
			read_save_count_reg <= to_unsigned(0, read_save_count_reg'length);
			print_counter_reg	<= to_unsigned(0, print_counter_reg'length);
			debounce_counter_reg<= to_unsigned(0, debounce_counter_reg'length);
		elsif (clock'event and clock = '1') then
			state_reg			<= state_next;
			write_issued_reg 	<= write_issued_next;
			data_received_reg	<= data_received_next;
			buffer_reg			<= buffer_next;
			write_data_reg		<= write_data_next;
			write_address_reg	<= write_address_next;
			write_counter_reg	<= write_counter_next;
			read_address_reg	<= read_address_next;
			read_req_count_reg	<= read_req_count_next;
			read_save_count_reg <= read_save_count_next;
			print_counter_reg	<= print_counter_next;
			debounce_counter_reg<= debounce_counter_next;
		end if;
	end process;

	process(state_reg, read_ready, write_ready, write_done, write_issued_reg, address, read_data_valid, read_data, data_received_reg, button_in,
			write_data_reg, write_address_reg, write_counter_reg, read_address_reg, read_req_count_reg, read_save_count_reg, 
			print_counter_reg, debounce_counter_reg, buffer_reg, read_length_const)
	begin
		state_next 			<= state_reg;
		write_issued_next 	<= write_issued_reg;
		data_received_next 	<= data_received_reg;
		buffer_next			<= buffer_reg;
		write_data_next		<= write_data_reg;
		write_address_next	<= write_address_reg;
		write_counter_next	<= write_counter_reg;
		write_req 			<= '0';
		read_req			<= '0';
		read_address_next	<= read_address_reg;		
		read_req_count_next	<= read_req_count_reg;
		read_save_count_next<= read_save_count_reg;
		print_counter_next	<= print_counter_reg;
		debounce_counter_next <= debounce_counter_reg;

		case state_reg is

			-- write a specific memory location
			when WRITE_STATE =>
				if (write_ready = '1') then
					write_req 			<= '1';
					write_address 		<= write_address_reg;
					write_data 			<= write_data_reg;
					state_next 			<= WRITE_WAIT_STATE;
				end if; 
			
			when WRITE_WAIT_STATE =>
				if (write_done = '1') then
					write_address_next	<= std_logic_vector( unsigned(write_address_reg) + 1);
					write_data_next		<= std_logic_vector( unsigned(write_data_reg) + 1);
					write_counter_next	<= write_counter_reg + 1;
					if (write_counter_reg = 9) then 
						state_next <= WAIT_STATE;
					else
						state_next <= WRITE_STATE;
					end if;
				end if;

			when WAIT_STATE =>
				if (button_in = '0') then
					state_next	<= READ_STATE;
				end if;
				
			-- read the written memory location and check the result
--			when READ_STATE =>
--				if (read_ready = '1' and read_req_count_reg < 7) then --7 read requests
--					read_req 				<= '1';
--					read_address 			<= read_address_reg;
--					--read_address_next		<= std_logic_vector( unsigned(read_address_reg) + 1);
--					read_length 			<= read_length_const;
--					read_req_count_next 	<= read_req_count_reg + 1;
--				end if;
--				if (read_data_valid = '1') then --and read_req_count_reg > 0) then
--					buffer_next(to_integer(read_save_count_reg))	<= read_data; 
--					read_save_count_next				<= read_save_count_reg + 1;
--					if (read_save_count_reg = 6) then
--						state_next	<= PRINT_STATE;
--					end if;
--				end if;

--			when READ_STATE =>
--				if (read_ready = '1') then 
--				if (read_req_count_reg = 0) then
--					read_req 				<= '1';
--					read_address 			<= read_address_reg;
--					read_length 			<= std_logic_vector(to_unsigned(4, read_length'length));--read_length_const;
--					read_req_count_next 	<= read_req_count_reg + 1;
--					state_next <= READ_WAIT_STATE;
--				else
--					read_req 				<= '1';
--					read_address 			<= std_logic_vector(unsigned(read_address_reg) + 4);
--					read_length 			<= std_logic_vector(to_unsigned(4, read_length'length));--read_length_const;
--					read_req_count_next 	<= read_req_count_reg + 1;
--					state_next <= READ_WAIT_STATE;
--				end if;
--				end if;

--MULTIPLE CONTINUOUS READ TEST
			when READ_STATE =>
				if (read_ready = '1') then
					--read_req_count_next 	<= read_req_count_reg + 1;
					read_req 				<= '1';
					read_address 			<= read_address_reg;
					read_length 			<= std_logic_vector(to_unsigned(8, read_length'length));--read_length_const;
					state_next				<= READ_WAIT_STATE;
				end if; 
				
			when READ_WAIT_STATE =>
				if (read_data_valid = '1') then
					buffer_next(to_integer(read_save_count_reg))	<= read_data; 
					read_save_count_next				<= read_save_count_reg + 1;
					if (read_save_count_reg = 7) then
					--	state_next	<= READ_STATE;
					--elsif (read_save_count_reg = 7) then 
						read_save_count_next <= (others => '0');
						state_next <= PRINT_STATE;
					end if;
				end if;

---SINGLE READ TEST
--			when READ_STATE =>
--				if (read_ready = '1') then
--					read_req 				<= '1';
--					read_address 			<= std_logic_vector(to_unsigned(5, read_address'length));--read_address_reg;
--					read_length 			<= std_logic_vector(to_unsigned(1, read_length'length));--read_length_const;
--					state_next 				<= READ_WAIT_STATE;
--				end if;			
--			when READ_WAIT_STATE =>
--				if (read_data_valid = '1') then
--					buffer_next(to_integer(read_save_count_reg))	<= read_data; 
--						state_next <= PRINT_STATE;
--				end if;
----

			when PRINT_STATE =>
				data_received_next <= buffer_reg(to_integer(print_counter_reg));
				--if (button_in = '0') then
					print_counter_next 	<= print_counter_reg + 1;
					state_next			<= DEBOUNCE_STATE;
					if (print_counter_reg >= 7) then
						print_counter_next <= to_unsigned(0, print_counter_next'length);
						state_next <= WAIT_STATE;
					end if;	
				--end if;

			when DEBOUNCE_STATE => 
				debounce_counter_next <= debounce_counter_reg + 1; 
				if (debounce_counter_reg > 50000000) then
					debounce_counter_next <= to_unsigned(0, debounce_counter_reg'length);
					state_next <= PRINT_STATE;
				end if;
				--if (button_in = '0') then
				--	state_next <= READ_STATE;
				--end if;

			when DEBOUNCE_STATE_2 => 
				debounce_counter_next <= debounce_counter_reg + 1; 
				if (debounce_counter_reg > 50000000) then
					debounce_counter_next <= to_unsigned(0, debounce_counter_reg'length);
					state_next <= READ_STATE;
				end if;


		end case;
	end process;

end architecture;