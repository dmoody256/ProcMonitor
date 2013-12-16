#! usr/bin/perl -w

=pod

 PREAMBLE
###
###############################################################################
###                 
### Classification : Unclassified
###
###############################################################################
###
### Source File Name : CPUutil.pl
###
###############################################################################
###
### Purpose :
### Module to monitor CPU and memory statistics on Solaris.
###
###############################################################################
###
### Limitations :
### None.
###
###############################################################################
###
### Modification History :
###  
### SCR
### Number         Date[dd/mm/yy] RSE[F. Last]     Description
###
###############################################################################
###

=cut

#control-f code: !@#00
#	!@#00 Subroutine Table of contents
#	!@#01 exit codes table
#	!@#02 monitor_interval()
#	!@#03 get_initial_cpu_times()
#	!@#04 get_final_stats()
#	!@#05 get_memory_config()
#	!@#06 string_formatter()
#	!@#07 get_position()
#	!@#08 get_position_default()
#	!@#09 build_array()
#	!@#10 get_cpu_info()
#	!@#11 process_opts()
#	!@#12 calculate_stats()
#	!@#13 remove_badopts()
#	!@#14 bubblesort()
#	!@#15 usage_sub()
#	!@#16 convert_csv()
#	!@#17 spacer()
#	!@#18 readstatus()
#	!@#19 readmemorysize()
#	!@#20 readcputime()
#	!@#21 timestruct2int()

# control-f: !@#01
# exit codes table
# 0  = Enter was pressed and/or script was successful
# 1  = Failed to get total physical memory
# 2  = Failed to get total virtual memory
# 3  = Failed to get number of CPUs
# 4  = No legal columns in option
# 5  = Tried to sort by non-existant column
# 6  = Invalid format in option
# 7  = Logfile could not be opened
# 8  = Top number of rows option was not an integer
# 9  = Runs option was not an integer
# 10 = Interval was not a numeric value
# 11 = Interval was less then .1

use strict;
use Getopt::Std; 
use IO::Select;  
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday);

# the default order to output in scalar and array form
my $DEFAULT_ORDER = 'pticvVmMn';
my @DEFAULT_ORDER_ARRAY = ('p', 't', 'i', 'c', 'v', 'V', 'm', 'M', 'n');

# the column label string in scalar and output form
my $LABEL_STRING = 'PID TPTIME IPTIME CPU% VMEM(kB) VMEM% PMEM(kB) PMEM% NAME';
my @LABEL_ARRAY = ('PID', 'RTIME', 'IRTIME', 'CPU%', 'VMEM(kB)', 'VMEM%',
                   'PMEM(kB)', 'PMEM%', 'NAME');

# the amount of space for each corresponding column
my @SPACE_ARRAY = (5,10,8,7,10,7,10,7,40);

my $global_total_CPU = 0; # used to sum the total CPU percent from all processes
my $intervals_run = 0; # counts the amount of loops run
my $start_time = time; # record the start time of this script

#get and process the options
my %opts;
getopts("o:s:f:l:n:i:r:u", \%opts);
process_opts(\%opts);

# assign the processed options to easy to read vairables
my $global_order = $opts{o}; # the order of columns
my $sort = $opts{s}; # the column to sort by
my $format = $opts{f}; # the output of the format
my $logFH = $opts{l}; # the output filehandle
my $top_num = $opts{n}; # the number of processes to display
my $interval = $opts{i}; # the time for the interval
my $runs = $opts{r}; # the number of intervals to run
my $usage = $opts{u}; # boolean to output usage documentation

# get the total virtual and physical memory of the system
my $mem_config_hash_ref = get_memory_config();
my $global_tot_pmem = $mem_config_hash_ref->{total_pmem};
my $global_tot_vmem = $mem_config_hash_ref->{total_vmem};

# get the number cpus available to the system
my $num_CPUs = get_cpu_info();

#start a select for STDIN so that we can read if enter was pressed
my $selectSTDIN = IO::Select->new();
$selectSTDIN->add(\*STDIN);

#the main loop that runs all intervals and prints output
while($runs > 0 || $runs == -1){

  $intervals_run++; 

  #run the interval monitor to get the stats for this interval
  my @stat_array = monitor_interval($interval);

  # if a column to sort by was specified then sort
  # will be a positive integer representing the column,
  # if the column did not exist then sort = -1
  if($sort != -1){

    # sort algorithm 
    @stat_array = bubblesort($sort, \@stat_array);
  }

  # calculate the new time
  my $time_run = time - $start_time;

  # calculate the total CPU used for the last interval
  $global_total_CPU = ($global_total_CPU/($interval*$num_CPUs))*100;
  
  if($global_total_CPU > 100){
    # the CPU was over 100% due to impercise measurements
    # making it look neat
    $global_total_CPU = 100.00;
  }
  else{
    # format the the percent to 2 decimal palces
    $global_total_CPU = sprintf("%.2f", $global_total_CPU);
  }
  
  # put the overall stat string into the front of the array
  unshift @stat_array, "Time Run: $time_run seconds, Measurements: $intervals_run, Total CPU%: $global_total_CPU\%\n";
  
  # time stamp it!
  my($sec,$usec) = gettimeofday();
  unshift @stat_array, "----> Time:$sec\.$usec <---0\n";
  
  # reset the CPU percent for the next round
  $global_total_CPU = 0;
  
  # convert the format is set
  if($format eq 'csv'){
    convert_csv(\@stat_array);
  }

  # print out a certain number of rows if option defined
  if(defined($top_num)){

    # only print out the max number of rows possible
    if($top_num > scalar(@stat_array)){
      $top_num = (scalar(@stat_array) - 1);
    }

    # loop through and print out each row
    for my $count (0..$top_num){

      # print to STDOUT or FH if option set
      if(defined($logFH)){
        print $logFH $stat_array[$count];
		print $logFH "\n";
      }
      else{
        print $stat_array[$count];
		print "\n";
      }
    }
  }
  # else print all rows
  else{
    if(defined($logFH)){
      print $logFH @stat_array;
	  print $logFH "\n";
    }
    else{
      print @stat_array;  
	  print "\n";
    }
  }
  
  # check input buffer to see if enter was pressed
  if($selectSTDIN->can_read(.0001)){
    if(defined($logFH)){
      close($logFH);
    }
    exit 0;
  }
  
  # decrement runs if the options was set
  if($runs > 0){
    $runs--;
  }
}

#control-f code: !@#02
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 monitor_interval
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will report CPU and Memory statistics over a given 
###     time interval.
###     
### (U) ABSTRACT:
###     The CPU will be monitored over the interval and determine how much
###     time each process gets on any given processor. It then reports the
###     total process time over its life and the time it got during the 
###     interval for each process. The memory statistics will also be 
###     reported at the end of the interval. Pyhsical memory space and 
###     virtual memory space will both be reported.   
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $interval   The time in seconds to monitor
###     return    @stat_array A sorted array that holds all the metrics
###
###############################################################################

=cut

sub monitor_interval{
  
  # the time interval to run over
  my $interval = shift; 

  # this equation was derived from rational equation regression
  # and the curve created by this equation creates a good offset
  # value at each interval value
  my $offsetadjust = ((1.8163*$interval+2.0408)/($interval + .102));
  
  # get the start of the offset time
  my $cpu_time1 = readcputime($$);

  # record the start cpu times
  my $start_hash_ref = get_initial_cpu_times();

  # get the end of the offset time
  my $cpu_time2 = readcputime($$);

  # calculate the offset, the offset is supposed to represent
  # the extra time it took for this script to process the times
  # of other processes
  my $offset = ($cpu_time2 - $cpu_time1)*($offsetadjust);
  
  # sleep for the interval - offset
  select(undef, undef, undef, ($interval-$offset));

  # get read the end times and do the calculation to get 
  # the final results
  my @stat_array = get_final_stats($start_hash_ref, $interval);

  return @stat_array;
}

#control-f code: !@#03
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_initial_cpu_times
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will get the start times for all the desired PIDs.
###     
### (U) ABSTRACT:
###     This subroutine will check to see if any PIDs were passed as command
###     line arguments or get all PIDs in the /proc/ directory. It then reads
###     the cpu time for each pid and stores it in a hash for later 
###     calculations.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     return \%start_hash A hash reference to the start times
###
###############################################################################

=cut

sub get_initial_cpu_times{

  my %start_hash;
  my @pid_array;

  # check to see if there are command line arguments
  if(@ARGV){

     # we are only interested in a few PIDs
     foreach my $pid (@ARGV){
       push @pid_array,$pid;
     }
  } 
  # else get all the PIDs from /proc
  else{
    opendir my $dir, '/proc/' or die $!;
    @pid_array = readdir $dir;
    closedir $dir;
  }

  # read the CPU time for each PID
  foreach my $pid (@pid_array){

    # skip the . and .. from /proc
    unless($pid =~ m/^\./){
      my $cpu_time = readcputime($pid);

      # -1 means that the pid file failed to open
      if($cpu_time == -1){
        next;
      }
      $start_hash{$pid} = $cpu_time;
    }
  }

  return \%start_hash;
}

#control-f code: !@#04
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_final_stats
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will get the end times for all the desired PIDS.
###     
### (U) ABSTRACT:
###     This subroutine will check to see if any PIDs were passed as command
###     line arguments or get all PIDs in the /proc/ directory. It then reads
###     the cpu time for each pid, performs calculations, creates the
###     stat string and formats each string for each pid.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $start_hash_ref The reference to the hash that holds the
###                               start cpu times
###     parameter $interval       The amount of time for the interval
###     return    @final_array    An array with all the stats
###
###############################################################################

=cut

sub get_final_stats{

  # start contains the start times of the cpu
  # interval is the time to sleep over
  my $start_hash_ref = shift;
  my $interval = shift;

  my @final_array;
  my @pid_array;

  # check to see if there are command line arguments
  if(@ARGV){

     # we are only interested in a few PIDs
     foreach my $pid (@ARGV){
       push @pid_array,$pid;
     }
  } 
  # else get all the PIDs from /proc
  else{
    opendir my $dir, '/proc/' or die $!;
    @pid_array = readdir $dir;
    closedir $dir;
  }

  # put the column label string in first
  my $column_string = string_formatter($LABEL_STRING);
  push @final_array, $column_string;

  # check all of the pids
  foreach my $pid (@pid_array){

    # make sure they are not the . and .. directories
    unless($pid =~ m/^\./){

      # calculate the stats
      $pid = calculate_stats($pid, $interval, $start_hash_ref);

      # if the pid file failed to open then skip it
      if($pid eq 'failed'){
	next;
      }
   
      # format the string
      $pid = string_formatter($pid);
      
      # pid stats are ready to go!
      push @final_array, $pid;
    }
  }

  return @final_array;	
}

#control-f code: !@#05
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_memory_config
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will get the system memory configuration.
###     
### (U) ABSTRACT:
###     This subroutine makes uses Solaris system commands to parse info 
###     about the current system. It will exit if system info can not be
###     gathered.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     return \%mem_hash A hash reference with system memory configuration
###
###############################################################################

=cut

sub get_memory_config{

  # run the system commands to get configuration
  my $phystring = `prtconf | grep Memory`;
  my $vrtstring = `swap -s`;
  
  # parse the physical memory values
  if($phystring =~ m/(\d+)\s(\w+)/){
    if($2 eq 'Megabytes'){
      $phystring = $1*1024;
    }
    else{
      $phystring = $1;
    } 
  }
  # failed to get system info better exit!
  else{
    print "Error getting system physical memory inside get_memory_config()\n";
    exit 1;
  }

  # parse the virtual memory values
  if($vrtstring =~ m/(\d+)\w\sused,\s(\d+)\w\savailable/){
    $vrtstring = $1 + $2;
  }
  # failed to get system info better exit!
  else{
    print "Error getting system virtual memory inside get_memory_config()\n";
    exit 2;
  }

  # store the values
  my %mem_hash;
  $mem_hash{total_pmem} = $phystring;
  $mem_hash{total_vmem} = $vrtstring;

  return \%mem_hash;
}

#control-f code: !@#06
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 string_formatter
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine takes the fully populated stat string and converts
###     to the correct order with correct columns.
###     
### (U) ABSTRACT:
###     This subroutine takes the default stat string with all the the columns
###     and formats it by creating a new string based off a input provided by
###     the user. Then any bad columns that don't belong are removed and the 
###     correct number of spaces are inserted between each column.
###     
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $format_string The string to be formatted
###     return    $final_string  The formatted string
###
###############################################################################

=cut

sub string_formatter{

  # get the string to be formatted
  my $format_string = shift;
  
  # create an array of the order of columns
  my @order_array = build_array($global_order);

  # get the variables ready for the loop
  my @format_array = split(" ", $format_string);
  my $final_string = '';
  my $com_select = 0;

  # loop through each column represented by a char
  # and add the corresponding column
  foreach my $char (@order_array){

    # get the position in the default columns
    # and skip this column if its non-existent
    my $pos = get_position_default($char);
    if($pos == -1){
      next;
    }
    
    # now add the correct spaces
    my $temp_string = spacer($SPACE_ARRAY[$pos], $format_array[$pos]);
   
    #insert an extra space
    $final_string .= $temp_string . ' ';
    
  } 
  
  #cap the string with a new line, its ready!
  $final_string .= "\n";
  
  return $final_string;
}

#control-f code: !@#07
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_position
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will take in a character and find its position in
###     the given string.
###     
### (U) ABSTRACT:
###     This subroutine looks through the passed order string and finds 
###     the position. It builds an array to search through, then checks to
###     make sure the character is in both the passed order and the default
###     order then returns the position.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $char        The character to check for
###     parameter $orderstring The string to check if the character is in
###     return    $pos         The postion of the character in orderstring
###     return    -1           The character was not found or legal
###
###############################################################################

=cut

sub get_position{

  my $char = shift;
  my $orderstring = shift;

  # create an array to search through easily
  my @order = build_array($orderstring);

  # search through the array and find the character
  for my $pos (0..(scalar(@order)-1)){
    if($char eq $order[$pos]){
      
      # if a match is found make sure it is a legal character
      if(get_position_default($char) >= 0){
        return $pos;
      }
    }  
  }
  
  # the character was not found or legal
  return -1;

}

#control-f code: !@#08
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_position_default
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will get the postion of a character from the default
###     order array.
###     
### (U) ABSTRACT:
###     None.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $char The character to check for
###     return    $pos  The postion of the character
###     return    -1    The character was not found
###
###############################################################################

=cut

sub get_position_default{

  my $char = shift;

  for my $pos (0..(scalar(@DEFAULT_ORDER_ARRAY)-1)){
    if($char eq $DEFAULT_ORDER_ARRAY[$pos]){
      return $pos;
    }  
  }
  return -1;
}

#control-f code: !@#09
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 build_array
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will build an array of characters from the 
###     given string.
###     
### (U) ABSTRACT:
###     None.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $string The character to check for
###     return    @array  The string in array form
###
###############################################################################

=cut

sub build_array{

  my $string = shift;

  my @array;
  for my $pos (0..(length($string)-1)){
    my $char = substr($string, $pos, 1);
    push @array, $char;
  }
  return @array;
}

#control-f code: !@#10
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 get_cpu_info
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine will get the number of virtual cores available to 
###     the system.
###     
### (U) ABSTRACT:
###     This subroutine uses the psrinfo system command to find information
###     about the systems processors. Each physical processor can have 
###     virutal processors that the OS will see. There can be multiple 
###     physical processors so each string of the output is searched and
###     the number of virtual processors is totaled up.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     return $cpu_count The number of CPUs
###
###############################################################################

=cut

sub  get_cpu_info{
  
  # use the system command to see how many virtual processors 
  my @cpu_array = `psrinfo -vp`;
  my $cpu_count = 0;

  # search through each string and find strings that say
  # how many virtual processors a physical processor has
  foreach my $string (@cpu_array){
    if($string =~ m/^The\sphysical\sprocessor\shas\s(\d+)/){
      $cpu_count += $1;
    }
  }
  # else we failed to get system configuration lets exit
  if($cpu_count == 0){
    print "Error getting CPUs inside get_cpu_info()\n";
    exit 3;
  }

  return $cpu_count;
 
}

#control-f code: !@#11
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 process_opts
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine processes the options given by the user and makes
###     checks and formats the options.
###     
### (U) ABSTRACT:
###     Each option is checked to see if there is a defined option, and if 
###     not a default value is chosen. If an option is invalid the script
###     exits and notifys the user.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $opts_hash_ref A reference to the hash holding options
###
###############################################################################

=cut

sub process_opts{

  # get the options hash
  my $opts_hash_ref = shift;

  # create easy to read variables for this subroutine
  my $order = $opts_hash_ref->{o};
  my $sort = $opts_hash_ref->{s};
  my $format = $opts_hash_ref->{f};
  my $logfile = $opts_hash_ref->{l};
  my $top_num = $opts_hash_ref->{n};
  my $interval = $opts_hash_ref->{i};
  my $runs = $opts_hash_ref->{r};
  my $usage = $opts_hash_ref->{u};
  my $logFH;

  # check order and make sure its defined
  unless(defined($order)){
    $order = $DEFAULT_ORDER;
  }
  # remove the illegal columns
  else{
    $order = remove_badopts($order);
	if($order eq ''){
	  print "No legal columns!\n";
	  exit 4;
	}
  }

  # check if sort is defined
  unless(defined($sort)){
    # if it is not defined find a possible column to sort by
    my @sort_array = ('i', 'p', 't', 'v', 'm', 'c', 'V', 'M');
    foreach my $char (@sort_array){
      $sort = get_position($char, $order);
      if($sort != -1){
        # if no columns to sort by are found then dont sort
        last;   
      }
    }
  }
  # else check the sort option is valid
  else{
    $sort = get_position($sort, $order);
    # -1 means the character didn't exist in the order option
    if($sort == -1){
      print "Can't sort by non-existent column!\n";
      exit 5;
    }
  }
 
  # check that output format is defined
  unless(defined($format)){
    $format = 'printout';
  }
  else{
    # lowercase it for next check
    $format = lc($format); 
  }

  # check for valid formats
  unless($format eq 'csv' || $format eq 'printout'){
    print "Unknown format!\n";
    exit 6;
  }

  # check that the logfile is valid and open it
  # and create a FH for it
  if(defined($logfile)){
    unless(open $logFH, ">>$logfile"){
      print "Logfile failed to open: $!\n";
      exit 7;
    }
  }

  # check that the top n option is valid
  if(defined($top_num)){
    if($top_num < 1 && $top_num =~ m/\D/){
      print "-n must positive integer!\n";
      exit 8;
    }
  }

  # check that the runs option is valid
  unless(defined($runs)){
    
	# -1 means run indefinetly
    $runs = -1;
  }
  elsif($runs < 1 && $runs =~ m/\D/){
    print "-r must positive integer!\n";
    exit 9;
  }

  # check that the interval option is valid
  unless(defined($interval)){
    $interval = 1;
  }
  elsif($interval < 1 && $interval =~ m/\D/){
      print "-i must positive integer!\n";
      exit 11;
  }
  

  # check if usage is defined and print usage
  if(defined($usage)){
    print usage_sub();
    exit 0;
  }

  #store the processed options into the opts hash
  $opts_hash_ref->{o} = $order;
  $opts_hash_ref->{s} = $sort;
  $opts_hash_ref->{f} = $format;
  $opts_hash_ref->{l} = $logFH;
  $opts_hash_ref->{n} = $top_num;
  $opts_hash_ref->{i} = $interval;
  $opts_hash_ref->{r} = $runs;
  $opts_hash_ref->{u} = $usage;

}

#control-f code: !@#12
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 calculate_stats
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine calculates the stats for each PID.
###     
### (U) ABSTRACT:
###     First the CPU finish time is read, then the memory is read. The
###     memory percent stats are then calculated and then time stats are 
###     calcualted. Finally the string is joined with spaces.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $pid         The pid of the process to calculate for
###     parameter $interval    The time interval that was measured over
###     parameter $hash_ref    The starting time hash reference
###     return    $stat_string The final string with all the stats
###
###############################################################################

=cut

sub calculate_stats{

  my $pid = shift;
  my $interval = shift;
  my $hash_ref = shift;

  my $irtime; # interval runtime
  my $cpu_percent;

  # get the final CPU time
  my $cpu_time = readcputime($pid);
  
  # if the pid file failed to read
  if($cpu_time == -1){
    return 'failed';
  }
  $cpu_time = sprintf("%.2f", $cpu_time);

  # get the memory stats
  my @mem_array = readmemorysize($pid);

  # seperate each value
  my $vmem = $mem_array[0];
  my $pmem = $mem_array[1];

  # this is the filename that was executed it will name the process
  my $fname = $mem_array[2];  

  # calculate the virtual memory percent
  my $vmem_percent = ($vmem/$global_tot_vmem)*100;
  $vmem_percent = sprintf("%.2f", $vmem_percent);

  # calculate the physical memory percent
  my $pmem_percent = ($pmem/$global_tot_pmem)*100;
  $pmem_percent = sprintf("%.2f", $pmem_percent);			
			
  # calculate the interval process time
  # hash_ref gets the start time for this pid 
  $irtime = $cpu_time - $hash_ref->{$pid};
  $cpu_percent = (($irtime)/$interval)*100;
  $irtime = sprintf("%.6f", $irtime);

  # sometimes if the interval is too short there
  # will be no time written yet for the finish time
  # so the number will be negative. We will just make this
  # 0 to represent almost no processing has been done
  if($irtime < 0){
    $irtime = 0;
    $cpu_percent = 0;
  }
  $cpu_percent = sprintf("%.2f", $cpu_percent);
  
  # this adds the current process time to the global
  # so that total CPU percent can be calculated
  $global_total_CPU += $irtime;
  
  # build the stat string to return it
  my $stat_string = "$pid $cpu_time $irtime $cpu_percent\% $vmem $vmem_percent\% $pmem $pmem_percent\% $fname";
  return $stat_string;
}

#control-f code: !@#13
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 remove_badopts
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine searches through the the order string and takes 
###     out any columns that are illegal.
###     
### (U) ABSTRACT:
###     None.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $order_string The string that represents the columns
###     return    $neworder     The legal order string
###
###############################################################################

=cut

sub remove_badopts{

  my $order_string = shift;

  # get an array to search through
  my @order_array = build_array($order_string);
  my $neworder = '';

  # check to make sure each character is legal
  foreach my $char (@order_array){
    if(get_position_default($char) > -1){
      # if the character is legal add it to the new order string
      $neworder .= $char
    }
  }
  return $neworder;
}

#control-f code: !@#14
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 bubblesort
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine sorts the stat array using the bubble sort algorithm.
###     
### (U) ABSTRACT:
###     The bubblesort algorithm works by checking each value against any
###     other value in an asecending or descending fashion. Each value is 
###     moved up the list 1 spot at a time until the value is less then 
###     higher spot. This algorithm works fairly well against semi sorted
###     listed. The subroutine checks to see which column we are sorting 
###     by and splits the stat string and to do the sort.
###     
### (U) LIMITATIONS:
###     None.
###
### (U) WAIVERS:
###     None.
###
###############################################################################
###
###     parameter $sorttype An integer representing which column to sort by
###     parameter $listref  This is a reference to the stat array
###     return    @list     A sorted array that holds all the metrics
###
###############################################################################

=cut

sub bubblesort{

  my $sorttype = shift;
  my $listref = shift;

  # build a new copy of the list
  my @list = @{$listref};

  # check to see if we need to remove the percent signs
  my @type_array = build_array($global_order);
  my $type = $type_array[$sorttype];

  # these are all columns that could have a percent
  if($type eq 'c' || $type eq 'V' || $type eq 'M'){
    
    # percet found true
    $type = 1;
  }
  # else percent found false
  else{
    $type = 0;
  }
  
  # loop through each element in the array
  # start at 1 because the label string is 0
  for my $pos (1..(scalar(@list)-1)){
    
    # now for each element move it up the list until the
    # next element is bigger
    my $i=1;
    while($i < (scalar(@list)-$pos)){
                      
      # get arrays to pick out the value we are comparing
      my @split_list = split(" ", ($list[$i]));
      my @split_list_next = split(" ", ($list[$i+1]));
     
      # get the current value and check if its defined
      # if not it means there is only 1 item in the string
      my $value1 = $split_list[$sorttype];
      unless(defined($value1)){
        $value1 = $list[$i];
      }
   
      # get the next value and check if its defined
      # if not it means there is only 1 item in the string
      my $value2 = $split_list_next[$sorttype];
      unless(defined($value2)){
        $value2 = $list[$i+1];
      }

      # remove the percent sign if necessary
      if($type){
        $value1 =~ s/%//;
        $value2 =~ s/%//;
      }

      # if the value is smaller move it up the list
      if($value1 <= $value2){
        my $temp = $list[$i];
        $list[$i] = $list[$i+1];
        $list[$i+1] = $temp;
      }    
      $i++;
    }
  }
  
  # sorted list is ready!
  return @list;
}

#control-f code: !@#15
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 usage_sub
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine prints out a usage statement.
###     
### (U) ABSTRACT:
###     None.
###
### (U) LIMITATIONS:
###     None.
###
### (U) WAIVERS:
###     None.
###
###############################################################################
###
###     return $usagestring A string describing this script
###
###############################################################################

=cut

sub usage_sub{
  my $usagestring = "###############################################################################\n".
  "\t\t\tCPUutil usage and manual.\n".
  "\n".
  "CPUutil monitors CPU and memory attributes over a time\n".
  "interval for Solaris 5.10. Each interval takes a snapshot\n".
  "measurement which can then be used to make observations\n".
  "and calculations such as averages. The output format and\n".
  "options are described below. Pressing the enter key will\n".
  "end the script at anytime.\n".
  "\n".
  "Output Format:\n".
  "Time Run: X seconds, Measurements: X, Total CPU%: X.XX%\n".
  "PID   TPTIME     IPTIME          CPU%    VMEM(kB)   VMEM%   PMEM(kB)   PMEM%   NAME               \n".
  "XXXXX XXXXXXXXXX XXXXXXXXXXXXXXX XXXXXXX XXXXXXXXXX XXXXXXX XXXXXXXXXX XXXXXXX XXXXXXXXXXXXXXXXXXX\n".
  "\n".
  "PID:\n".
  "\tThe process PID number.\n".
  "TPTIME:\n".
  "\tThe Total Process TIME in seconds for the process. This\n".
  "\tis the total time the process has been processing in a CPU.\n".
  "\tThis is a snapshot measurement taken at the end of the interval.\n".
  "IPTIME:\n".
  "\tThe Interval Process TIME in seconds for the process. This\n".
  "\tis the total time the process has been processing in a CPU for\n".
  "\tthe given interval time. This is calculated by measuring the\n".
  "\ttotal run time at the beginning of the interval and subtracting\n".
  "\tthat from the total run time at the end of the interval.\n".
  "CPU%:\n".
  "\tThe percent of the interval that the process got to process\n".
  "\tin a CPU. This is equal to IPTIME divided by the interval time.\n".
  "VMEM(kB):\n".
  "\tThe Virtual MEMory used by the process in Kilobytes.\n".
  "\tThis is a snapshot measurement taken at the end of the interval.\n".
  "VMEM%:\n".
  "\tThe percent of virtual memory used from the total amount\n".
  "\tof virtual memory available to the system. The total amount\n".
  "\tof virtual memory is queried by the 'swap -s' command at the\n".
  "\tbegining of this script.\n".
  "PMEM(kB):\n".
  "\tThe Physical MEMory used by the process in Kilobytes.\n".
  "\tThis is a snapshot measurement taken at the end of the interval.\n".
  "PMEM%:\n".
  "\tThe percent of physical memory used from the physical\n".
  "\taddress space of RAM avaialable to the system. The total amount\n".
  "\tof physical memory is queried by the 'prtconf' command at the\n".
  "\tbegining of this script.\n".
  "NAME:\n".
  "\tThe fileNAME that was called to execute this process.\n".
  "Time Run:\n".
  "\tThe time in seconds that CPUutil has been alive.\n".
  "Measurements:\n".
  "\tThe number of intervals run.\n".
  "Total CPU%:\n".
  "\tA sum total of the CPU usage by all processes for the interval.\n".
  "\n".
  "Arguments and Options:\n".
  "\n".
  "The script takes space seperated command line arguments,\n".
  "that are PID numbers to monitor specifically. The less PIDs\n".
  "that are tracked the faster this script can run. For example,\n".
  "'perl CPUutil 2 4325 24931' will monitor only processes with\n".
  "those pids if they exists.\n".
  "\n".
  " -o (order):\n".
  "\tTakes a single string value that represents the\n". 
  "\torder for output to be displayed. The default order value\n".
  "\tused if this option is unset is 'pticvVmMn' with each character\n".
  "\trepresenting a field as follows:\n".
  "\t\tp = PID\n".
  "\t\tt = TPTIME\n".
  "\t\ti = IPTIME\n".
  "\t\tc = CPU%\n".
  "\t\tv = VMEM(kB)\n".
  "\t\tV = VMEM%\n".
  "\t\tm = PMEM(kB)\n".
  "\t\tM = PMEM%\n".
  "\t\tn = NAME\n".
  "\tEach field is not required for output to be displayed and\n".
  "\tfields can be output twice. For example, '-o irtpirtm' is a\n".
  "\tlegal input.\n".
  " -s (sort):\n".
  "\tTakes a single character that represents a field\n".
  "\tas described in the default order option previously, and\n".
  "\tsorts the output in a ascending order using bubble sort\n".
  "\talgorithm. For example to sort by PID, use '-s p'.\n".
  " -f (format):\n".
  "\tTakes a case insensitve string as input to\n".
  "\tchange the default output. The output can be set to a\n".
  "\tCSV (Comma Seperated Values) output by using '-f csv'. The\n".
  "\tdefault 'printout' and 'csv' are the only output available\n".
  "\tcurrently.\n".
  " -l (logfile):\n".
  "\tTakes a string that is the filepath to a\n".
  "\tlogfile, for example '-l log.txt'. The script attempts\n".
  "\tto open or create the file and exits on failure. All\n".
  "\toutput is written by appending to the file.\n".
  " -n (top n-rows):\n".
  "\tPrints the top n-rows only, for example\n".
  "\t'-n 10' prints the top ten rows. If unset all rows\n".
  "\tare printed.\n".
  " -i (interval):\n".
  "\tTakes a integer number that represents time in\n".
  "\tseconds to run the interval, for example '-i 2' takes\n".
  "\tmeasurements every 2 seconds, the default is 1 second.\n". 
  " -r (runs):\n".
  "\tThe number of intervals to run, for example '-r 10'\n".
  "\twill run 10 intervals then exit. If unset, the script\n".
  "\twill run indefinetly untill the enter key is press.\n".
  "\n".
  "Written by Daniel Moody at LM SSC, daniel.m.moody\@lmco.com\n";

  return $usagestring;
}

#control-f code: !@#16
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 convert_csv
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine goes through the stat array and formats every string
###     to be a CSV (comma seperated values) format.
###     
### (U) ABSTRACT:
###     None.
###
### (U) LIMITATIONS:
###     None.
###
### (U) WAIVERS:
###     None.
###
###############################################################################
###
###     parameter $array_ref The reference to the stat_array
###
###############################################################################

=cut

sub convert_csv{

  my $array_ref = shift;

  # the overall stats need to be handle specifically
  @{$array_ref}[1] =~ s/Time\sRun:\s(\d+)\sseconds/TimeRun,$1/;
  @{$array_ref}[1] =~ s/\sMeasurements:\s(\d+)/Measurements,$1/;
  @{$array_ref}[1] =~ s/\sTotal\sCPU%:\s(\d+\.\d+)%/TotalCPU%,$1/;

  # the rest of the strings can be handled the same
  for my $pos (1..(scalar(@{$array_ref})-1)){
    @{$array_ref}[$pos] =~ s/\s+/\,/g;
    @{$array_ref}[$pos] =~ s/\%//;
    @{$array_ref}[$pos] =~ s/\,$/\n/;
  }	
}

#control-f code: !@#17
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 spacer
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine takes a string and formats it by adding the correct
###     number of spaces.
###     
### (U) ABSTRACT:
###     This subroutine will check the string to see if it is larger or 
###     smaller then the corresponding values in the @SPACE_ARRAY. It then 
###     adds or subtracts spaces and characters until the string is just right.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $totalspace The total number of spaces for this column
###     parameter $string     The string to be formatted
###     return    $string     The formatted string
###
###############################################################################

=cut

sub spacer{

  my $totalspace = shift;
  my $string = shift;

  # calculate the number of spaces we are off by
  my $numspace = $totalspace - length($string);

  # we need to add space
  if($numspace > 0){
    for (0..($numspace-1)){
      $string .= ' ';
    }
    return $string;
  }
  
  # we need to get rid of characters
  elsif($numspace < 0){
    return substr($string, 0, $totalspace);
  }
  
  # the string is already good
  else{
    return $string;
  }
}

#control-f code: !@#18
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 readstatus
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine reads the pid status file.
###     
### (U) ABSTRACT:
###     This subroutine is not used by this script but is placed in here
###     for useful information and reference.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $pid The pid we are looking for in /proc
###     return    0    The file was read
###     return    -1   The file failed to be read
###
###############################################################################

=cut

sub readstatus{

  my $pid = shift;
  my $status;
  my $STATUS;

  if(open($STATUS,"/proc/$pid/status")){
    
	# read the 128 bits of the status file
    read($STATUS, $status, 128);
    close($STATUS);

	# unpack the status file written by Brendon Gregg 09-May-2005
    my ($pr_flags,   # int pr_flags /* flags (see below) */
        $pr_nlwp,    # int pr_nlwp /* number of active lwps in the process */
        $pr_pid,     # pid_t pr_pid /* process id */
        $pr_ppid,    # pid_t pr_ppid /* parent process id */
        $pr_pgid,    # pid_t pr_pgid /* process group id */
        $pr_sid,     # pid_t pr_sid /* session id */
        $pr_aslwpid, # id_t pr_aslwpid /* obsolete */
        $pr_agentid, # id_t pr_agentid /* lwp-id of the agent lwp, if any */
        $pr_sigpend, # sigset_t pr_sigpend /* set of process pending signals */
        $pr_brkbase, # uintptr_t pr_brkbase /* virtual address of the process heap */
        $pr_brksize, # size_t pr_brksize /* size of the process heap, in bytes */
        $pr_stkbase, # uintptr_t pr_stkbase /* virtual address of the process stack */
        $pr_stksize, # size_t pr_stksize /* size of the process stack, in bytes */
        $pr_utime,   # timestruc_t pr_utime /* process user cpu time */
        $pr_stime,   # timestruc_t pr_stime /* process system cpu time */
        $pr_cutime,  # timestruc_t pr_cutime /* sum of children's user times */
        $pr_cstime,  # timestruc_t pr_cstime /* sum of children's system times */
        $filler) = 
        unpack("iiiiiiiia16iiiia8a8a8a8a", $status);

    return 0;
  }
  else{
    return -1;
  }
}

#control-f code: !@#19
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 readmemorysize
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine reads the pid psinfo file.
###     
### (U) ABSTRACT:
###     We only use the rss, virtual memory and filename from this file.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $pid          The pid we are looking for in /proc
###     return    @return_array An array that holds the info
###     return    -1            The file failed to be read
###
###############################################################################

=cut

sub readmemorysize{

  my $pid = shift;
  my $psinfo;
  my $PSINFO;
	
  # attempt to read 256 bytes from the pid psinfo file	
  if(open($PSINFO,"/proc/$pid/psinfo")){
    read($PSINFO, $psinfo, 256);
    close($PSINFO);

	# unpack the psinfo file written by Brendon Gregg 09-May-2005
    my ($pr_flag,   # int pr_flag /* process flags */
        $pr_nlwp,   # int pr_nlwp /* number of active lwps in the process */
        $pr_pid,    # pid_t pr_pid /* process id */
        $pr_ppid,   # pid_t pr_ppid /* process id of parent */
        $pr_pgid,   # pid_t pr_pgid /* process id of process group leader */
        $pr_sid,    # pid_t pr_sid /* session id */
        $pr_uid,    # uid_t pr_uid /* real user id */
        $pr_euid,   # uid_t pr_euid /* effective user id */
        $pr_gid,    # gid_t pr_gid /* real group id */
        $pr_egid,   # gid_t pr_egid /* effective group id */
        $pr_addr,   # uintptr_t pr_addr /* address of process */
        $pr_size,   # size_t pr_size /* size of process image in Kbytes */
        $pr_rssize, # size_t pr_rssize /* resident set size in Kbytes */
        $pr_pad1,   # padding?
        $pr_ttydev, # dev_t pr_ttydev /* controlling tty device (or PRNODEV) */
        $pr_pctcpu, # ushort_t pr_pctcpu /* % of recent cpu time used by all lwps */
        $pr_pctmem, # ushort_t pr_pctmem /* % of system memory used by process */
        $pr_start,  # timestruc_t pr_start /* process start time, from the epoch */
        $pr_time,   # timestruc_t pr_time /* cpu time for this process */
        $pr_ctime,  # timestruc_t pr_ctime /* cpu time for reaped children */
        $pr_fname,  # char pr_fname[PRFNSZ] /* name of exec'ed file */
        $pr_psargs, # char pr_psargs[PRARGSZ] /* initial characters of arg list */
        $pr_wstat,  # int pr_wstat /* if zombie, the wait() status */
        $pr_argc,   # int pr_argc /* initial argument count */
        $pr_argv,   # uintptr_t pr_argv /* address of initial argument vector */
        $pr_envp,   # uintptr_t pr_envp /* address of initial environment vector */
        $pr_dmodel, # char pr_dmodel /* data model of the process */
        $pr_taskid, # taskid_t pr_taskid /* task id */
        $pr_projid, # projid_t pr_projid /* project id */
        $pr_nzomb,  # int pr_nzomb /* number of zombie lwps in the process */
        $filler) = 
        unpack("iiiiiiiiiiIiiiiSSa8a8a8Z16Z80iiIIaa3iiiia", $psinfo);

    # put desired info into array to return
    my @return_array = ($pr_size, $pr_rssize, $pr_fname);
    return @return_array;
	
  }
  else{
		
    return -1;
  }
}

#control-f code: !@#20
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 readcputime
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine reads the pid status file.
###     
### (U) ABSTRACT:
###     None.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $pid The total number of spaces for this column
###     return    0 The formatted string
###
###############################################################################

=cut

sub readcputime{
	
  my $pid = shift;
  my $usage;
  my $USAGE;

  # attempt to read 256 bytes from the pid usage file
  if(open($USAGE,"/proc/$pid/usage")){
    read($USAGE, $usage, 256);
    close($USAGE);
	
	# unpack the usage file written by Brendon Gregg 09-May-2005
    my ($pr_lwpid,    # id_t pr_lwpid /* lwp id.  0: process or defunct */
        $pr_count,    # int pr_count /* number of contributing lwps */
        $pr_tstamp,   # timestruc_t pr_tstamp /* real time stamp, time of read() */
        $pr_create,   # timestruc_t pr_create /* process/lwp creation time stamp */
        $pr_term,     # timestruc_t pr_term /* process/lwp termination time stamp */
        $pr_rtime,    # timestruc_t pr_rtime /* total lwp real (elapsed) time */
        $pr_utime,    # timestruc_t pr_utime /* user level CPU time */
        $pr_stime,    # timestruc_t pr_stime /* system call CPU time */
        $pr_ttime,    # timestruc_t pr_ttime /* other system trap CPU time */
        $pr_tftime,   # timestruc_t pr_tftime /* text page fault sleep time */
        $pr_dftime,   # timestruc_t pr_dftime /* data page fault sleep time */
        $pr_kftime,   # timestruc_t pr_kftime /* kernel page fault sleep time */
        $pr_ltime,    # timestruc_t pr_ltime /* user lock wait sleep time */
        $pr_slptime,  # timestruc_t pr_slptime /* all other sleep time */
        $pr_wtime,    # timestruc_t pr_wtime /* wait-cpu (latency) time */
        $pr_stoptime, # timestruc_t pr_stoptime /* stopped time */
        $filltime,    # padding? 
        $pr_minf,     # ulong_t pr_minf /* minor page faults */
        $pr_majf,     # ulong_t pr_majf /* major page faults */
        $pr_nswap,    # ulong_t pr_nswap /* swaps */
        $pr_inblk,    # ulong_t pr_inblk /* input blocks */
        $pr_oublk,    # ulong_t pr_oublk /* output blocks */
        $pr_msnd,     # ulong_t pr_msnd /* messages sent */
        $pr_mrcv,     # ulong_t pr_mrcv /* messages received */
        $pr_sigs,     # ulong_t pr_sigs /* signals received */
        $pr_vctx,     # ulong_t pr_vctx /* voluntary context switches */
        $pr_ictx,     # ulong_t pr_ictx /* involuntary context switches */
        $pr_sysc,     # ulong_t pr_sysc /* system calls */
        $pr_ioch,     # ulong_t pr_ioch /* chars read and written */
        $filler) = 
        unpack("iia8a8a8a8a8a8a8a8a8a8a8a8a8a848LLLLLLLLLLLLa40", $usage);

	# we just want the user and sys time on the cpu
    my $time = timestruct2int($pr_utime) + timestruct2int($pr_stime);
    return $time;
  }
  #failed to read the file
  else{
    return -1;
  }
}

#control-f code: !@#21
=pod

 SUBROUTINE
###############################################################################
###                 
###                 UNCLASSIFIED
###
###                 SYSTEM SUPPORT SOFTWARE ITEM
###
###                 timestruct2int
###
###                 SUBROUTINE BODY
###
###############################################################################
###
### (U) DESCRIPTION:
###     This subroutine unpacks the time struct from the /proc files.
###     
### (U) ABSTRACT:
###     None.
###     
### (U) LIMITATIONS:
###     None.
###
###############################################################################
###
###     parameter $timestruct The timestruct object
###     return    $time       The time in seconds
###
###############################################################################

=cut

sub timestruct2int{

  my $timestruct = shift;
  my $secs = 0;
  my $nsecs = 0; 
  
  # unpack the timestruct written by Brendon Gregg 09-May-2005
  ($secs,$nsecs) = unpack("LL", $timestruct);
  my $time = $secs + $nsecs * 10**-9;
  return $time;
}

#The End