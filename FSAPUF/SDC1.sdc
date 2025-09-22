#create_clock -name mainclk -period 20.000 [get_ports {mainclock}]
#set_clock_uncertainty -to [get_clocks {mainclk}] 0.10
#set_false_path -from [get_ports {mainreset}]
#set_false_path -to   [get_ports {mainreset}]
# main system clock you already have
create_clock -name mainclk -period 20.000 [get_ports mainclock]
set_clock_uncertainty -to [get_clocks mainclk] 0.10

# asynchronous reset cut
set_false_path -from [get_ports mainreset]
set_false_path -to   [get_ports mainreset]

# define a virtual external clock for outputs
#create_clock -name virt_out -period 20.000

# give the tail ports an output requirement (0 ns here = “just analyze it”)
#set_output_delay -clock virt_out 0.000 [get_ports tailer0]
