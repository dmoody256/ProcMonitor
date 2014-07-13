#! usr/bin/perl -w

#control-f code: !@#00
# !@#00 Subroutine Table of contents
# !@#01 PrintStats
# !@#02 kill
# !@#03 RecordMeasureStats
# !@#04 CalcAverages
# !@#05 ReadLog
# !@#06 ReadSection
# !@#07 SortDataByMeasure
# !@#08 GetCPUInfo
# !@#09 SortProcInfo
# !@#10 PrintHeader
# !@#11 GetPIDs
# !@#12 GetMemoryInfo
# !@#13 Mygettimeofday
# !@#14 ProcessOpts
# !@#15 ReadProcFile
# !@#16 timestruct2int
# !@#17 Usage

use strict;
use Getopt::Std;                        #module for reading switches from the command line 
use Time::HiRes qw(gettimeofday);       #get current time in seconds and microseconds
use Scalar::Util qw(looks_like_number); #check to see if a variable is numeric

$SIG{INT} = 'kill'; #control-C signal run kill subroutine
$|++;               #print STDOUT without buffering

#get and process the options
my %opts;
unless(getopts("i:d:r:a:h", \%opts)){
  die "Usage: ProcMonitor.pl\t[-a running_average] [-i interval] [-r runs]\n\t\t\t[-d dir_name] [-h]\n";
}
ProcessOpts(\%opts);

# Main executable variables
my $interval = $opts{i};       # the time for the interval
my $runs = $opts{r};           # the number of intervals to run
my $average_period = $opts{a}; # time period in seconds to average over
my %GLOBAL_master_hash;        # hash to hold all other hashes
my $logFH;                     # the log file file handle
my $current_measure = 0;       # current measure we are on

#open the log file for writing
my $log_file = 'proclog';  
open $logFH, ">$log_file" or die "Could not open logfile $log_file: $!\n";

# print a header contain start and system information
PrintHeader($logFH);

# get the start time for calculating the offset
my $start_time = Mygettimeofday();
print "Recording processes.";

# record the initial proc stats
RecordMeasureStats($logFH, $current_measure);

# while loop to record each pids stats after each time interval
while($runs > 0 || $runs == -1){

  # calculations to prepare the offset
  my $current_time = Mygettimeofday();
  my $offset = $current_time - $start_time;
  if($offset > $interval){
    $offset = 0;
  }

  # increment times and measures
  $current_measure++; 
  $start_time += $interval;

  # sleep for the interval
  select(undef, undef, undef, ($interval-$offset));

  # get the new proc stats
  RecordMeasureStats($logFH, $current_measure);
  
  # decrement loop exit condition
  if($runs > 0){
    $runs--;
  }
  
  # alert user that process has completed a loop
  if($runs != 0){
    print ".";
  }
}

# close log so it can be opened for reading
close $logFH;

# read all the stats into the global hash
print "Reading the logs...\n";
ReadLog($log_file);

# sort and calculate the stats intos arrays based on pid and measure
# and store them in the global hash
print "Sorting the data...\n";
SortProcInfo();

# calculate the the running averages over the time period given
print "Calculating the averages...\n";
CalcAverages($average_period);

# resort the stats into a measure then pid style for easier printing
print "Sorting the data...\n";
$GLOBAL_master_hash{'measure_pid_hash'}     = SortDataByMeasure($GLOBAL_master_hash{'pid_measure_hash'});
$GLOBAL_master_hash{'measure_pid_avg_hash'} = SortDataByMeasure($GLOBAL_master_hash{'pid_measure_avg_hash'});

# print all the stats to the corresponding logs
print "Writing the reports...\n";
PrintStats();

print "Complete!\n";

exit 0;

=pod
=head1 PrintStats
 
The directory will contain stats for total, averages, a master stat 
file, per process stats and averages, and the original log created.
This is called at the end of the script excustion to create the stats
file.

inputs:
  None

output:
  None

=cut

#control-f code: !@#01

sub PrintStats{

  #get references for each of the hashes to print
  my $pid_measure_hash_ref        = $GLOBAL_master_hash{'pid_measure_hash'};
  my $measure_pid_hash_ref        = $GLOBAL_master_hash{'measure_pid_hash'};
  my $measure_totals_hash_ref     = $GLOBAL_master_hash{'measure_totals_hash'};
  my $pid_measure_avg_hash_ref    = $GLOBAL_master_hash{'pid_measure_avg_hash'};
  my $measure_pid_avg_hash_ref    = $GLOBAL_master_hash{'measure_pid_avg_hash'};
  my $measure_totals_avg_hash_ref = $GLOBAL_master_hash{'measure_totals_avg_hash'};

  #create the per process directory
  my $proc_dir = 'per_proc_stats';
  mkdir $proc_dir;
 
  #create the per process averages directory
  my $avg_dir = 'per_proc_avg';
  mkdir $avg_dir;

  # create the label strings
  my $label = 'DATETIME,MEASURE,PROCESSNAME,PID,TIMESTAMP,INTERVAL,PROCESSTIME,CPU%,VMEM(kB),VMEM%,PMEM(kB),PMEM%,IO(kB)';
  my $totals_label = 'MEASURE,PIDCOUNT,STARTTIME,AVGINTERVAL,PROCESSTIME,CPU%,VMEM(kB),VMEM%,PMEM(kB),PMEM%,IO(kB)';

  #these loops prints a file for the stats of each pid
  foreach my $pid (keys %{$pid_measure_hash_ref}){

    if(open my $FH, ">$proc_dir/$pid.csv"){
      print $FH "$label\n"; 

      foreach my $measure (sort { $a <=> $b} keys %{$pid_measure_hash_ref->{$pid}}){
        next if($measure == 0);

        chomp @{$pid_measure_hash_ref->{$pid}{$measure}};

        if(defined(@{$pid_measure_hash_ref->{$pid}{$measure}})){ 
          my $string = join(',', @{$pid_measure_hash_ref->{$pid}{$measure}});
          print $FH "$string\n"; 
        }
      }
      close $FH;
    }
  }

  # this loop prints all the stats into a single file
  if(open my $FH, ">stats.csv"){
    print $FH "$label\n"; 

    foreach my $measure (sort { $a <=> $b} keys %{$measure_pid_hash_ref}){
      next if($measure == 0);
  
      foreach my $pid (sort { $a <=> $b} keys %{$measure_pid_hash_ref->{$measure}}){
       
        chomp @{$measure_pid_hash_ref->{$measure}{$pid}};
  
        if(defined(@{$measure_pid_hash_ref->{$measure}{$pid}})){ 
          my $string = join(',', @{$measure_pid_hash_ref->{$measure}{$pid}});
          print $FH "$string\n"; 
        }
      }
    }
    close $FH;
  }
  
  # this loop prints each measures totals
  if(open my $FH, ">totals.csv"){
    print $FH "$totals_label\n";

    foreach my $measure (sort {$a <=> $b} keys %{$measure_totals_hash_ref}){
      next if($measure == 0);

      chomp @{$measure_totals_hash_ref->{$measure}};

      my $string = join(',', @{$measure_totals_hash_ref->{$measure}});
      print $FH "$measure,$string\n";
    }
    close $FH;
  }

  # these loops print each pids averages into  a seperate file
  foreach my $pid (keys %{$pid_measure_avg_hash_ref}){

    if(open my $FH, ">$avg_dir/$pid.csv"){
      print $FH "$label\n"; 

      foreach my $measure (sort { $a <=> $b} keys %{$pid_measure_avg_hash_ref->{$pid}}){
        next if($measure == 0);

        chomp @{$pid_measure_avg_hash_ref->{$pid}{$measure}};

        if(defined(@{$pid_measure_avg_hash_ref->{$pid}{$measure}})){ 
          my $string = join(',', @{$pid_measure_avg_hash_ref->{$pid}{$measure}});
          print $FH "$string\n"; 
        }
      }
      close $FH;
    }
  }
  
  # these loops print all the averages into a single file
  if(open my $FH, ">avgs.csv"){
    print $FH "$label\n"; 

    foreach my $measure (sort { $a <=> $b} keys %{$measure_pid_avg_hash_ref}){
      next if($measure == 0);
  
      foreach my $pid (sort { $a <=> $b} keys %{$measure_pid_avg_hash_ref->{$measure}}){
       
        chomp @{$measure_pid_avg_hash_ref->{$measure}{$pid}};
  
         if(defined(@{$measure_pid_avg_hash_ref->{$measure}{$pid}})){ 
          my $string = join(',', @{$measure_pid_avg_hash_ref->{$measure}{$pid}});
          print $FH "$string\n"; 
        }
      }
    }
    close $FH;
  }
 
  # this loops prints the totals averages
  if(open my $FH, ">avgtotals.csv"){
    print $FH "$totals_label\n";

    foreach my $measure (sort {$a <=> $b} keys %{$measure_totals_avg_hash_ref}){
      next if($measure == 0);

      chomp @{$measure_totals_avg_hash_ref->{$measure}};

      my $string = join(',', @{$measure_totals_avg_hash_ref->{$measure}});
      print $FH "$measure,$string\n";
    }
    close $FH;
  }

}

=pod

=head1 kill
 
This subroutine will end the recording loop when ctrl-C is caught.

inputs:
  None

output:
  None

=cut

#control-f code: !@#02

sub kill{
  print "\nEnd signal received\n";
  $runs = 0;
}

=pod

=head1 RecordMeasureStats

This subroutine will loop through all the pids, read the proc stats
and record the stats to the log.

inputs:
  $FH - the log filehandle to print to.
  $measure - the current measure we are on.

output:
  None

=cut

#control-f code: !@#03

sub RecordMeasureStats{

  my $FH = shift;
  my $measure = shift;

  # get all the pids from the proc directory
  my @pid_array = GetPIDs();

  # read the proc data and print to the log
  foreach my $pid (@pid_array){
    my @proc_data = ReadProcFile($pid);
    #                   4:timestamp   3:process time   0:virtual memory 1:pyhsical memory 5:io data   2: name
    print $FH "$measure,$proc_data[4],$pid,$proc_data[3],$proc_data[0],$proc_data[1],$proc_data[5],$proc_data[2]\n";
  } 
}

=pod

=head1 CalcAverages

The subroutine will look at each stat, then loop through each of the
previous stats adding up the time it took to take the measurement, 
summing each stat, and recording the number of sums made. it will stop
summing when the total time it has gone back is more then the running 
passed in. Then it creates a new hash and puts the running averages for
both the process stats and the measure totals.

inputs:
  $average_period - the time in seconds to check back and average over

outputs:
  None

=cut

#control-f code: !@#04

sub CalcAverages{

  my $average_period = shift;

  #get the total and process stats
  my $pid_measure_hash_ref = $GLOBAL_master_hash{'pid_measure_hash'};
  my $measure_totals_hash_ref = $GLOBAL_master_hash{'measure_totals_hash'};
  
  #create the new hashes
  my %pid_measure_avg_hash;
  my %measure_totals_avg_hash;
  
  #first lets get the process averages
  foreach my $pid (keys %{$pid_measure_hash_ref}){
    my %measure_hash;

    foreach my $measure (sort {$b <=> $a } keys %{$pid_measure_hash_ref->{$pid}}){

      #skip measure 0 (un-useable data) and undefined values
      next if($measure == 0); 
      next unless(defined(@{$pid_measure_hash_ref->{$pid}{$measure}}));

      my @avg_array;
  
      # initialize the average array
      for my $pos (0..(scalar(@{$pid_measure_hash_ref->{$pid}{$measure}})-1)){
          $avg_array[$pos] = $pid_measure_hash_ref->{$pid}{$measure}[$pos];
      }

      # the current number of measure we are looking back and 
      # the current number of measure we have used for the average
      my $look_back = 0; 
      my $sums_count = 1; 

      # loop untill the sum of the interval (position 5) is greater then the
      # the running average period, or we run out of measure to look back on
      while($avg_array[5] < $average_period && $measure-$look_back > 0){
        $look_back++;

        # skip if undefined or the previous measure, the proc failed
        next unless(defined(@{$pid_measure_hash_ref->{$pid}{$measure-$look_back}}));
        next if($pid_measure_hash_ref->{$pid}{$measure-$look_back}[2] eq 'proc_failed');

        # sum the previous measure for the variable values which start after position 5
        for my $pos (5..(scalar(@avg_array)-1)){
          $avg_array[$pos] += $pid_measure_hash_ref->{$pid}{$measure-$look_back}[$pos];
        }
        $sums_count++;
      }
      
      # now calculate the averages
      for my $pos (5..(scalar(@avg_array)-1)){
        $avg_array[$pos] = $avg_array[$pos]/$sums_count;
      }

      $measure_hash{$measure} = \@avg_array;
    }  
    $pid_measure_avg_hash{$pid} = \%measure_hash;
  }

  # now we do the averages for the totals
  foreach my $measure (sort {$b <=> $a} keys %{$measure_totals_hash_ref}){ 

    #skip measure 0 (un-useable data) and undefined values
    next if($measure == 0);
    next unless(defined(@{$measure_totals_hash_ref->{$measure}}));

    my @avg_array;

    # initialize the averages array
    for my $pos (0..(scalar(@{$measure_totals_hash_ref->{$measure}})-1)){
      $avg_array[$pos] = $measure_totals_hash_ref->{$measure}[$pos];   
    }
    
    # the current number of measure we are looking back and 
    # the current number of measure we have used for the average
    my $look_back = 0; 
    my $sums_count = 1; 

    # loop untill the sum of the interval (position 2) is greater then the
    # the running average period, or we run out of measure to look back on
    while($avg_array[2] < $average_period && $measure-$look_back > 0){
      $look_back++;

      # measure 0 has un-useable data
      next if($measure-$look_back == 0);
 
      # sum each of the values
      for my $pos (0..(scalar(@{$measure_totals_hash_ref->{$measure-$look_back}})-1)){
        $avg_array[$pos] += $measure_totals_hash_ref->{$measure-$look_back}[$pos];
      }
      $sums_count++; 
    }

    # now calculate the averages
    for my $pos (0..(scalar(@avg_array)-1)){
      $avg_array[$pos] = $avg_array[$pos]/$sums_count;
    }
    $measure_totals_avg_hash{$measure} = \@avg_array;
  }

  # store the averages
  $GLOBAL_master_hash{'pid_measure_avg_hash'}    = \%pid_measure_avg_hash;
  $GLOBAL_master_hash{'measure_totals_avg_hash'} = \%measure_totals_avg_hash;

}

=pod

=head1 ReadLog

This subroutine will read the values from the log and place them in a 
array inside a hash according the pid and measure.

inputs:
  $log_file - the log to read from

output:
  None

=cut

#control-f code: !@#05

sub ReadLog{

  my $log_file = shift;
  
  # subroutine variables
  my @header; # the header information
  my %proc; # the process information
  my $read_section = 0; #current section we are reading
  my $logFH;

  open $logFH, "<$log_file" or die "could not open logfile $log_file: $!\n";

  # read each line of the log file and organize it
  while(my $line = <$logFH>){

    # switch section will return a -1 if a new section is encountered
    my $switch_section = SetReadSection($line, \$read_section);

    if($switch_section == -1){ 
      next; #new section encoutnered, read section value has been changed
    }
 
    #reading in header info
    elsif($read_section == 0){
       push @header, $line;
    }

    #reading in process info
    elsif($read_section == 1){
      my @line_array = split(',', $line);
      my $measure = $line_array[0];
      my $pid = $line_array[2];
     
      if(defined($pid)){
        $proc{$pid}{$measure} = \@line_array;
      }
      else{ #new pid found
        my %measure_hash;
        $measure_hash{$measure} =  \@line_array;
        $proc{$pid} = \%measure_hash;
      }
    }
  }

  $GLOBAL_master_hash{'header_array'} = \@header;
  $GLOBAL_master_hash{'proc_hash'}    = \%proc;
}

=pod

=head1 ReadSection

This subroutine will dectect if a new section is encoutner and will
switch values to signal a new section.

inputs:
  $line - the log to read from
  $read_section_ref - reference to the read section variable

ouput:
  -1 if a switch secton has been found

=cut

#control-f code: !@#06

sub SetReadSection{
  my $line = shift;
  my $read_section_ref = shift;
 
  # process section found
  if($line =~ m/^\-+Proc_Stats\-+/){
    ${$read_section_ref} = 1;
    return -1;
  }
  else{ # no new section found
    return ${$read_section_ref};
  }
}

=pod

=head1 SortDataByMeasure

This subroutine will loop through a hash of stats sort by pids and then
and then measures, and will resort it by measures then pids.

inputs:
  $pid_measure_hash_ref - the hash reference to the pid by measure hash

output:
  a hash reference to a measure by pid hash

=cut

#control-f code: !@#07

sub SortDataByMeasure{

  my $pid_measure_hash_ref = shift;

  my %measure_hash;

  # find each stat array and the place it into the correct position in the new
  # hash
  foreach my $measure (keys %{$GLOBAL_master_hash{'measure_totals_hash'}}){
    my %pid_hash;
    foreach my $pid (keys %{$pid_measure_hash_ref}){
      $pid_hash{$pid} = \@{$pid_measure_hash_ref->{$pid}{$measure}};
    }
    $measure_hash{$measure} = \%pid_hash;
  }
  return \%measure_hash;
}

=pod

=head1 GetCPUInfo

This subroutine uses the psrinfo system command to find information
about the systems processors. Each physical processor can have 
virutal processors that the OS will see. There can be multiple 
physical processors so each string of the output is searched and
the number of virtual processors is totaled up.

inputs:
  None

output:
  $cpu_count - The number of CPUs

=cut

#control-f code: !@#08

sub  GetCPUInfo{
  
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
    print "Error getting CPUs inside GetCPUInfo()\n";
    exit 3;
  }

  return $cpu_count;
 
}

=pod

=head1 SortProcInfo

This subroutine will loop through the raw stat data and make calculations
and sort the data. It also generates the totals for each measure.

inputs:
  None

outputs:
  return - a hash reference to a measure by pid hash

=cut

#control-f code: !@#09

sub SortProcInfo{

  my @header_array = @{$GLOBAL_master_hash{'header_array'}};
  my %proc_hash = %{$GLOBAL_master_hash{'proc_hash'}};

  #the new hashes
  my %table_hash;
  my %measure_totals_hash;

  # get variables to make calculations
  my $system_time = $header_array[8] - $header_array[10];
  my $CPUcount = $header_array [2];
  my $total_vmem = $header_array[4];
  my $total_pmem = $header_array[6];
  
  # check each raw log stat found
  foreach my $pid (keys %proc_hash){
    foreach my $measure (keys %{$proc_hash{$pid}}){
     
      # get the raw stats an put them into easier to read variables for calculations
      my ($measure_filler, $boottime, $pid, $cpu_time, $vmem, $pmem, $io_bytes, $name ) = @{$proc_hash{$pid}{$measure}};
      
      # declarations for the calculations          
      my $cpu_percent;
      my $time_interval;
      my $vmem_percent;
      my $pmem_percent;
      my $io_kb;
      my @stat_array;
      my $error_flag = 0;

      # checks to make sure the proc made a succesful read and that 
      # there is a previous value to calculate against
      if(defined($proc_hash{$pid}{$measure-1}) && $boottime != -1 && $cpu_time  != -1){

        # calculate the time
        my $time = $system_time+$boottime;
        my $timestamp = $time;
        $time = sprintf("%.3f", $time);
        $time =~ s/(\d+)(\.\d*)/$1/;
        my $useconds = $2;
        $time = localtime($time);
        $time =~ s/(\d*:\d\d:\d\d)/$1$useconds/;

        # calculate the cpu time and interval
        $cpu_time = $cpu_time - $proc_hash{$pid}{$measure-1}[3];
        $time_interval = $boottime - $proc_hash{$pid}{$measure-1}[1];
        
        $io_bytes = $io_bytes - $proc_hash{$pid}{$measure-1}[6];
      
        # there was an error prevent illegal divide by 0
        if($time_interval == 0){
          $time_interval = 1;
          $error_flag = 1;
        }

        # format the values
        $cpu_percent = sprintf("%.2f", ((($cpu_time/$time_interval)*100)/$CPUcount));
        $vmem_percent = sprintf("%.2f", $vmem/$total_vmem);
        $pmem_percent = sprintf("%.2f", $pmem/$total_pmem);
        $io_kb = sprintf("%.2f", $io_bytes/1024);

        # create new array to be stored
        @stat_array = ($time,$measure,$name,$pid,$timestamp,$time_interval,$cpu_time,
                      $cpu_percent,$vmem,$vmem_percent,$pmem,$pmem_percent,
                      $io_kb);
      }
      else{
        $error_flag = 1;
      }

      # handle the errors
      if($error_flag){

        my $time = $header_array[8];
        my $timestamp = $time;
        $time = sprintf("%.3f", $time);
        $time =~ s/(\d+)(\.\d*)/$1/;
        my $useconds = $2;
        $time = localtime($time);
        $time =~ s/(\d*:\d\d:\d\d)/$1$useconds/; 
        @stat_array = ($time,$measure,'proc_failed',$pid,$timestamp,$interval,0,
                      0,0,0.0,0,0.0,0);

      }

      # calculate the totals for this measure
      if(defined($measure_totals_hash{$measure})){
        
        #find the min time for to determine when this interval actually started
        if($measure_totals_hash{$measure}[1] > $stat_array[4] && $stat_array[4] != $header_array[8]){
          $measure_totals_hash{$measure}[1] = $stat_array[4]; 
        }
       
        # increase the pid count
        $measure_totals_hash{$measure}[0]++; 

        # make the summation for the total
        for my $count (2..9){
          $measure_totals_hash{$measure}[$count] += $stat_array[$count+3];
        }
      }
      else{ # first time this measure has been encountered, we need to initialize
        my @totals_array = (1, $stat_array[4], $time_interval, $cpu_time, $cpu_percent,$vmem,$vmem_percent,$pmem,$pmem_percent,$io_kb);
        $measure_totals_hash{$measure} = \@totals_array;
      }
    
      # store the array
      if(defined($table_hash{$pid})){
        $table_hash{$pid}{$measure} = \@stat_array;
      }
      else{ # first time this pid has been encounter, we need ot create a new hash
        my %measure_hash;
        $measure_hash{$measure} = \@stat_array;
        $table_hash{$pid} = \%measure_hash;
      }
    }
  }

  # divide the total interval time by the total pids to find the average interval for this measure
  foreach my $measure (%measure_totals_hash){
    if(defined($measure_totals_hash{$measure})){
      $measure_totals_hash{$measure}[2] = $measure_totals_hash{$measure}[2]/$measure_totals_hash{$measure}[0];
    }
    else{
      delete $measure_totals_hash{$measure};
    }
  }

  $GLOBAL_master_hash{'pid_measure_hash'}    = \%table_hash;
  $GLOBAL_master_hash{'measure_totals_hash'} = \%measure_totals_hash;
}

=pod

=head1 PrintHeader

This subroutine will get some system information and print the it to the
logfile.

inputs:
  $FH - the log file handle to print to.

output:
  None

=cut

#control-f code: !@#10

sub PrintHeader{

  my $FH = shift;

  # get the system info
  my $LABEL_STRING = "----------------------------------Proc_Stats-----------------------------------\n";
  my $computer = `uname -a`;
  my ($total_vmem, $total_pmem) = GetMemoryInfo();
  my $CPUcount = GetCPUInfo();
  my $intervals_run = 0; 
  my $bootime = (ReadProcFile($$))[4];
  my $starttime = Mygettimeofday();

  # put the values togehter and print the strings
  my $header_string =
  "uname -a: $computer".
  "Number of CPUs:\n".
  "$CPUcount\n".
  "Total Virtual Memory in kB:\n".
  "$total_vmem\n".
  "Total Physical Memory in kB:\n".
  "$total_pmem\n".
  "Script Start Time:\n".
  "$starttime\n".
  "System Boot Time:\n".
  "$bootime\n".
  "Running Average: $opts{a} seconds\n".
  "Interval: $opts{i} seconds\n";
   
  print $FH $header_string;
  print $FH $LABEL_STRING; 

}

=pod

=head1 GetPIDs

This subroutine will get all the current pids in the proc directory.

inputs:
  None

outputs:
  @pid_array - a new array of current pids.

=cut

#control-f code: !@#11

sub GetPIDs{

  my @pid_array;

  # get the pids
  opendir my $dirFH, '/proc/' or die $!;
  @pid_array = readdir $dirFH;
  close $dirFH;

  # get rid of the . and .. values
  shift @pid_array; 
  shift @pid_array;
  
  return @pid_array;
}

=pod

=head1 GetMemoryInfo
 
This subroutine makes uses Solaris system commands to parse info 
about the current system. It will exit if system info can not be
gathered.

inputs:
  None

ouput:
  @mem_array - an array with the memory values

=cut

#control-f code: !@#12

sub GetMemoryInfo{

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
    print "Error getting system physical memory inside GetMemoryInfo()\n";
    exit 1;
  }

  # parse the virtual memory values
  if($vrtstring =~ m/(\d+)\w\sused,\s(\d+)\w\savailable/){
    $vrtstring = $1 + $2;
  }
  # failed to get system info better exit!
  else{
    print "Error getting system virtual memory inside GetMemoryInfo()\n";
    exit 2;
  }

  # store the values
  my @mem_array = ($vrtstring, $phystring);

  return @mem_array;
}

=pod

=head1 Mygettimeofday

This is a wrapper for the gettimeofday subroutine and does string 
concatenation for a truer time value.

inputs:
  None.

ouput:
  $time - a precise time measurement

=cut

#control-f code: !@#13

sub Mygettimeofday{
  my ($sec,$usec) = gettimeofday();
  my $time = "$sec\.$usec";
  return $time;
}

=pod

=head1 ProcessOpts

Each option is checked to see if there is a defined option, and if 
not a default value is chosen. If an option is invalid the script
exits and notifys the user.

inputs:
  $opts_hash_ref - A reference to the hash holding options

ouput:
  None

=cut

#control-f code: !@#14

sub ProcessOpts{

  # get the options hash
  my $opts_hash_ref = shift;

  # create easy to read variables for this subroutine
  my $interval = $opts_hash_ref->{i};
  my $runs = $opts_hash_ref->{r};
  my $dirname = $opts_hash_ref->{d};
  my $average = $opts_hash_ref->{a};
  
  # process the directory name
  # and create a defualt if one is not provided
  if($opts_hash_ref->{h}){
    Usage();
  }

  unless(defined($dirname)){

    my @date = localtime(time);
    my $day = $date[3];
    my $month = $date[4]+1;
    my $year = $date[5] + 1900;
    $dirname = "ProcMonitor_$month-$day-${year}_test";
    my $count = 0;
    my $temp = $dirname . $count;
    while(-e $temp){
      $count++;
      $temp = $dirname . $count;
    }

    unless(mkdir $temp){
      die "unable to make directory $temp : $!\n";
    }
    chdir $temp;

  }
  else{
    unless(mkdir $dirname){
      die "unable to make directory $dirname : $!\n";
    }
    chdir $dirname;
  } 

  # check to make sure the average value is valid
  unless(defined($average)){
    $average = 10;
  }
  elsif($average < 1 && $average =~ m/\D/){
    print "-a must positive integer!\n";
    exit 9;
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
 
  #store the processed options into the opts hash
  $opts_hash_ref->{i} = $interval;
  $opts_hash_ref->{r} = $runs;
  $opts_hash_ref->{a} = $average;
 
}

=pod

=head1 ReadProcFile

This subroutine reads the proc files.

inputs:
  $pid - the pid to check

output:
  @return_array - the proc info packaged

=cut

#control-f code: !@#15

sub ReadProcFile{
	
  my $pid = shift;

  my $usage;
  my $USAGE;
  my $psinfo;
  my $PSINFO;
  my @return_array;

	
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
        $filler) = unpack("iiiiiiiiiiIiiiiSSa8a8a8Z16Z80iiIIaa3iiiia", $psinfo);

    # put desired info into array to return
   my $fname = (split(' ', $pr_psargs))[0];
   unless(defined($fname)){
     $fname = '';
   }
   
   push @return_array, ($pr_size, $pr_rssize, $fname , timestruct2int($pr_time));
	
  }
  else{
    push @return_array, (-1,-1,'open_failed',-1);
  }

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
        unpack("iia8a8a8a8a8a8a8a8a8a8a8a8a8a8a48LLLLLLLLLLLLa40", $usage);
        
    push @return_array, (timestruct2int($pr_tstamp), $pr_ioch);		
  }
  #failed to read the file
  else{
    push @return_array, (-1, -1);		
  }

  return @return_array;
}

=pod

=head1 timestruct2int

This subroutine unpacks the time struct from the /proc files.

inputs:
  $timestruct - The timestruct object

output:
  $time - The time in seconds

=cut

#control-f code: !@#16

sub timestruct2int{

  my $timestruct = shift;
  my $secs = 0;
  my $nsecs = 0; 
  
  # unpack the timestruct written by Brendon Gregg 09-May-2005
  ($secs,$nsecs) = unpack("LL", $timestruct);
  my $time = $secs + $nsecs * 10**-9;
  return $time;
}

=pod

=head1 Usage

This subroutine prints out a usage statement.

inputs:
  None

output:
  $usagestring A string describing this script

=cut

#control-f code: !@#17

sub Usage{
  
  my $time = Mygettimeofday;
  $time = sprintf("%.3f", $time);
  $time =~ s/(\d+)(\.\d*)/$1/;
  my $useconds = $2;
  $time = localtime($time);
  $time =~ s/(\d*:\d\d:\d\d)/$1$useconds/;

  my $usagestring = 
  "#########################################################################\n".
                "\t\tProcMonitor.pl usage and manual.\n".
  "\n".
  "ProcMonitor.pl monitors CPU and memory attributes over a time\n".
  "interval for Solaris 5.10. Each interval takes a snapshot\n".
  "measurement which can then be used to make observations\n".
  "and calculations such as averages. The output format and\n".
  "options are described below. Pressing the Conrtol-C will\n".
  "end the monitor process, and began the post processing.\n".
  "\n".
  "ProcMonitor.pl will read and record /proc filesystem stats\n".
  "for each pid. After the recording period is over, post\n".
  "processing will be done, and output files will be recorded\n".
  "into a directory passed by the -d option, or a default\n".
  "directory explained below. The files will be generated for\n".
  "each process including averages and totals. The files will\n".
  "all be in a Comma Seperated Value (CSV) format. Read below\n".
  "for a detailed description of each of the columns.\n".
  "\n".
  "#########################################################################\n".
  "Options:\n".
  "-a running_average: This is the amount of time in seconds\n".
        "\tthat the running average should be taken over. The default\n".
        "\tis 10 seconds.\n".
  "-i interval: This is the time the interval should try to run\n".
        "\tover in seconds. The interval will be increased under\n".
        "\thigh CPU and process load. The default is 1 second.\n".
  "-r runs: A certain number of measures to take. The default is\n".
        "\tto run indefinetly till control-C is pressed.\n".
  "-d directory: This is the directory to create the stat data files\n".
         "\tin. The default will be a directory created in the pwd with\n".
         "\ta generic name as in e.g. ProcMonitor_MM_DD_YYYY_testX\n".
  "-h: Print out this manual.\n".
  "\n".
  "#########################################################################\n".
  "PID stat file columns in order:\n".
  "'DATETIME': This column is a timestamp of the exact\n".
        "\ttime the record was taken. It is the following\n".
        "\tformat: Weekday Month Day Hours:Min:Sec:uSec Year,\n".
        "\te.g. $time\n".
  "'MEASURE': The current measurement interval this was taken on.\n".
  "'PROCESSNAME': The name of the executed file.\n".
  "'PID': The PID number of the process.\n".
  "'TIMESTAMP': A numerical precise timestamp in seconds since\n".
        "\tthe beginning of the epoch.\n".
  "'INTERVAL': The interval in seconds that this measurement\n".
        "\twas made over.\n".
  "'PROCESSTIME': The amount of processor time in seconds the\n".
        "\tthe process recieved over the time interval.\n".
  "'CPU%': The calculated CPU utilization over the time period.\n".
  "'VMEM(kB)': The size of the virtual memory this process holds.\n".
  "'VMEM%': The percent of virtual memory out of total system\n".
         "\tvirtual memory.\n".
  "'PMEM(kB)': The size of the physical memory this process holds.\n".
  "'PMEM%': The percent of physical memory out of total system\n".
         "\tphysical memory.\n".
  "'IO(kB)': The amount of chars read or written by the process\n".
         "\tover the time interval. This is not nessarily disk\n".
         "\twrites or reads.\n".
  "\n".
  "#########################################################################\n".
  "Total file columns in order:\n".
  "'MEASURE': The current measure for this total.\n".
  "'PIDCOUNT': The total number of pids found during the interval.\n".
  "'STARTTIME': The time the first process was recorded for this\n".
         "\tinterval.\n".
  "'AVGINTERVAL': The average interval for all PIDs during this\n".
         "\tmeasure\n".
  "'PROCESSTIME': The total processor time for all PIDs during\n".
         "\tthis measure\n".
  "'CPU%': Total CPU utilization during this measure.\n".
  "'VMEM(kB)': Total virtual memory used at the end of this measure.\n".
  "'VMEM%': Perecnt of total virtual memory used at the end of this\n".
         "\tmeasure.\n".
  "'PMEM(kB)': Total physical memory used at the end of this measure.\n".
  "'PMEM%': Perecnt of total physical memory used at the end of this\n".
         "\tmeasure.\n".
  "'IO(kB)': Total chars read or written during this measure.\n".
  "\n".
  "#########################################################################\n".
  "Written by Daniel Moody, dmoody256\@gmail.com\n";

  print $usagestring;
  exit 0;
}

#The End
