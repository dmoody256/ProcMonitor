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

use strict;
use Getopt::Std; 
use Time::HiRes qw(gettimeofday);
use Scalar::Util qw(looks_like_number);

$SIG{INT} = 'kill';
$SIG{CHLD} = 'IGNORE';

#get and process the options
my %opts;
getopts("i:f:r:d", \%opts);
process_opts(\%opts);

my $dirname = $opts{f}; # the output filehandle
my $interval = $opts{i}; # the time for the interval
my $runs = $opts{r}; # the number of intervals to run

my $dtrace_fork = -1;
my $mpstat_fork = -1;
my $dir;
my @pid_array;
my $logFH;

if(@ARGV){
  foreach my $pid (@ARGV){
    push @pid_array,$pid;
  } 
}

my $current_measure = 0;
my $logfile = 'proclog';
my $dtrace_logfile = 'dtracelog';
my $mpstat_logfile = 'mpstatlog';
MakeDir($dirname);

my %bin_measure;
my %init_bin_pid;

GetPIDs(\@pid_array);
foreach my $pid (@pid_array){
  $init_bin_pid{$pid} = ReadProcFile($pid);
}
$bin_measure{$current_measure} = \%init_bin_pid;

while($runs > 0 || $runs == -1){
  
  $current_measure++; 
  
  if(defined($opts{d})){
    $dtrace_fork = fork;
    if($dtrace_fork == 0){
      $SIG{INT} = 'IGNORE';
      PrintDtrace($interval, $current_measure, $dtrace_logfile);
      exit 0;
    }
  }
  
  $mpstat_fork = fork;
  if($mpstat_fork == 0){
    $SIG{INT} = 'IGNORE';
    GetPIDs(\@pid_array);
    PrintMpstat($interval, $current_measure, $mpstat_logfile);
    exit 0;
  }
  
  my %bin_pid;
  sleep($interval);
  GetPIDs(\@pid_array, $dir);
  foreach my $pid (@pid_array){
    $bin_pid{$pid} = ReadProcFile($pid);
  }
  $bin_measure{$current_measure} = \%bin_pid;

  if($runs > 0){
    $runs--;
  }
}



sub UnkpackProcBinData{

  my $bin_measure_pid_ref = shift;
  my $logfile = shift;

  my $LABEL_STRING = "----------------------------------Proc_Stats-----------------------------------\n";
  my $header_string = GetHeaderString();
  

  open $logFH, ">$logfile" or die "Could not open logfile $logfile: $!\n";

  print $logFH $header_string;
  print $logFH $LABEL_STRING; 


  
  foreach my $measure (keys %{$bin_measure_pid_ref}){
    foreach my $pid (keys %{$bin_measure_pid_ref->{$measure}}){
      if($bin_measure_pid_ref->{$measure}{$pid}{psinfo} eq -1 || $bin_measure_pid_ref->{$measure}{$pid}{usage} eq -1){
         print $logFH "$measure,-1,$pid,-1,-1,-1,-1,open_failed\n";
         next;
      }
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
        $filler) = unpack("iiiiiiiiiiIiiiiSSa8a8a8Z16Z80iiIIaa3iiiia", $bin_measure_pid_ref->{$measure}{$pid}{psinfo});

     

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
        $filler2) = 
        unpack("iia8a8a8a8a8a8a8a8a8a8a8a8a8a8a48LLLLLLLLLLLLa40", $bin_measure_pid_ref->{$measure}{$pid}{usage});

      # put desired info into array to return
      my $fname = (split(' ', $pr_psargs))[0];
      unless(defined($fname)){
        $fname = '';
      }
      my $timestamp = timestruct2int($pr_tstamp);
      my $processtime = timestruct2int($pr_ctime);

      print $logFH "$measure,$timestamp,$pid,$processtime,$pr_size,$pr_rssize,$pr_ioch,$fname\n";
    }
  }

  close $logFH;
}

UnkpackProcBinData(\%bin_measure, $logfile);

print "Letting threads finish...\n";
sleep $interval + 1;

my $merged_log = MergeLogs($logfile, $mpstat_logfile, $dtrace_logfile);

my @ref_array = ReadLog($merged_log);

my @header_array = @{$ref_array[0]};
my %proc_hash    = %{$ref_array[1]};
my %mpstat_hash  = %{$ref_array[2]};
my %dtrace_hash  = %{$ref_array[3]};

@ref_array = SortProcInfo(\@header_array, \%proc_hash);

InsertMpstatInfo(\%mpstat_hash, $ref_array[1]);

my %pid_measure_hash = %{$ref_array[0]};
my %measure_totals_hash = %{$ref_array[1]};

if($opts{d}){

foreach my $measure (keys %dtrace_hash){
  ParseDtrace($dtrace_hash{$measure}, $measure, $interval, \%pid_measure_hash);
}

SumDtrace( \%pid_measure_hash, \%measure_totals_hash);

}

my %measure_pid_hash = SortDataByMeasure(\%measure_totals_hash, \%pid_measure_hash );



my $proc_dir = 'per_proc_stats';
mkdir $proc_dir;

my $label = 'DATETIME,MEASURE,PROCESSNAME,PID,TIMESTAMP,INTERVAL,PROCESSTIME,CPU%,VMEM(kB),VMEM%,PMEM(kB),PMEM%,IO(kB)';
my $totals_label = 'MEASURE,PIDCOUNT,CALCCPU%,MPUSR,MPSYS,MPIDLE,AVGINTERVAL,PROCESSTIME,VMEM(kB),VMEM%,PMEM(kB),PMEM%,';
if($opts{d}){
  $label .= ',DSKUTIL%,DSKIO(kB),DSKACCESSCOUNT\n'
}
else{
  $label .= '\n'
}

foreach my $pid (keys %pid_measure_hash){
  if(open my $FH, ">$proc_dir/$pid"){
    print $FH "$label\n"; 
    foreach my $measure (sort { $a <=> $b} keys %{$pid_measure_hash{$pid}}){
      next if($measure == 0);
      chomp @{$pid_measure_hash{$pid}{$measure}};
      if(defined(@{$pid_measure_hash{$pid}{$measure}})){ 
        my $string = join(',', @{$pid_measure_hash{$pid}{$measure}});
        print $FH "$string\n"; 
      }
      else{
        delete $pid_measure_hash{$pid}{$measure};
      }
    }
    close $FH;
  }
}

if(open my $FH, ">stats"){
  print $FH "$label\n"; 
  foreach my $measure (sort { $a <=> $b} keys %measure_pid_hash){
    next if($measure == 0);

    foreach my $pid (sort { $a <=> $b} keys %{$measure_pid_hash{$measure}}){
     
      chomp @{$measure_pid_hash{$measure}{$pid}};

      if(defined(@{$measure_pid_hash{$measure}{$pid}})){ 
        my $string = join(',', @{$measure_pid_hash{$measure}{$pid}});
        print $FH "$string\n"; 
      }
      else{
        delete $measure_pid_hash{$measure}{$pid}
      }
    }
  }
  close $FH;
}

if(open my $FH, ">totals"){
  
  foreach my $measure (sort {$a <=> $b} keys %measure_totals_hash){
    next if($measure == 0);
    chomp @{$measure_totals_hash{$measure}};
    my $string = join(',', @{$measure_totals_hash{$measure}});
    print $FH "$measure,$string\n";
  }
  close $FH;
}

sub kill{
  unless(defined($mpstat_fork)){
    $mpstat_fork = -1;
  }

  unless(defined($dtrace_fork)){
    $dtrace_fork = -1;
  }

  if($dtrace_fork != 0 && $mpstat_fork != 0){
    print "\nEnd signal received, starting post processing...\n";
  }
  $runs = 0;
}

sub MakeDir{
  
  my $dirname = shift; 
  
  unless(defined($dirname)){

    my @date = localtime(time);
    my $day = $date[3];
    my $month = $date[4];
    my $year = $date[5] + 1900;
    $dirname = "CPUutil_$month-$day-${year}_test";
    my $count = 0;
    my $temp = $dirname . $count;
    while(-e $temp){
      $count++;
      $temp = $dirname . $count;
    }

    mkdir $temp;
    chdir $temp;

  }
  else{
     mkdir $dirname;
     chdir $dirname;
  } 
 
}

sub ReadLog{

  my $logfile = shift;
  
  my @header;
  my %proc;
  my %mpstat;
  my %dtrace;
  my $read_section = 0;
  my $logFH;

  print "Reading the logfile...\n";

  open $logFH, "<$logfile" or die "could not open logfile $logfile: $!\n";

  while(my $line = <$logFH>){
    my $switch_section = SetReadSection($line, \$read_section);

    if($switch_section == -1){ 
      next;
    }
    elsif($read_section == 0){
       push @header, $line;
    }
    elsif($read_section == 1){
      my @line_array = split(',', $line);
      my $measure = $line_array[0];
      my $pid = $line_array[2];
     
      if(defined($pid)){
        $proc{$pid}{$measure} = \@line_array;
      }
      else{
        my %measure_hash;
        $measure_hash{$measure} =  \@line_array;
        $proc{$pid} = \%measure_hash;
      }
    }
    elsif($read_section == 2){
      if($line =~ m/END\sMPSTAT/){
        next;
      }
 
      my $CPUcount = $header[2];
    
      my @line_array = split(',', $line);
      my $measure = $line_array[1];
      my $timestamp = $line_array[2];
  
      for my $count (0..($CPUcount+1)){
        $line = <$logFH>;
        if($line =~ m/END\sMPSTAT/){
          last;
        }
      }
      if($line =~ m/END\sMPSTAT/){
        next;
      }
      my @sum;
      for my $count (0..($CPUcount-1)){
        $line = <$logFH>;
        $line = "$line_array[1] $line_array[2]".$line;
        my @overal_CPU = split(' ', $line);
        
        if($count != 0){
          my $pos = 0;
          foreach my $value (@overal_CPU){
            $sum[$pos] += $value;
            $pos++;
          }
        }
        else{
          my $pos = 0;
          foreach my $value (@overal_CPU){
            $sum[$pos] = $overal_CPU[$pos];
            $pos++;
          }
        }
      }
      $sum[1] = $sum[1]/$CPUcount;
      $sum[14] = $sum[14]/$CPUcount;
      $sum[15] = $sum[15]/$CPUcount;
      $sum[17] = $sum[17]/$CPUcount;
      $mpstat{$measure} = \@sum;
    
    }
    elsif($read_section == 3){

      my @dtrace_measure;
      my @line_array = split(',', $line);
      my $measure = $line_array[1];
      my $timestamp = $line_array[2];

      while( $line = <$logFH>){
        if($line =~ m/END\sDTRACE\sMEASURE/){
          last;
        }

        unless($line eq ''){
          push @dtrace_measure, $line;
        }
      }
      $dtrace{$measure} = \@dtrace_measure;
    }
  }

  my @array = (\@header,\%proc,\%mpstat,\%dtrace);
  return @array;
}


sub SetReadSection{
  my $line = shift;
  my $read_section_ref = shift;

  if($line =~ m/^\-+Proc_Stats\-+/){
    ${$read_section_ref} = 1;
    return -1;
  }
  elsif($line =~ m/^\-+Mpstat_Stats\-+/){
    ${$read_section_ref} = 2;
    return -1;
  }
  elsif($line =~ m/^\-+Dtrace_Stats\-+/){
    ${$read_section_ref} = 3;
    return -1;
  }
  else{
    return ${$read_section_ref};
  }

  
}

sub SortDataByMeasure{

  my $measure_totals_hash_ref = shift;
  my $pid_measure_hash_ref = shift;

  my %measure_hash;
  foreach my $measure (keys %measure_totals_hash){
    my %pid_hash;
    foreach my $pid (keys %pid_measure_hash){
      $pid_hash{$pid} = \@{$pid_measure_hash{$pid}{$measure}};
    }
    $measure_hash{$measure} = \%pid_hash;
  }
  return %measure_hash;
}

sub InsertMpstatInfo{

  my $mpstat_hash_ref = shift;
  my $measure_totals_hash_ref = shift;

  foreach my $measure (keys %{$mpstat_hash_ref}){
    my @new_array = ($measure_totals_hash_ref->{$measure}[0], 
                     $measure_totals_hash_ref->{$measure}[4], 
                     $mpstat_hash_ref->{$measure}[14],        
                     $mpstat_hash_ref->{$measure}[15], 
                     $mpstat_hash_ref->{$measure}[17],        
                     $measure_totals_hash_ref->{$measure}[2], 
                     $measure_totals_hash_ref->{$measure}[3],
                     $measure_totals_hash_ref->{$measure}[5], 
                     $measure_totals_hash_ref->{$measure}[6],
                     $measure_totals_hash_ref->{$measure}[7], 
                     $measure_totals_hash_ref->{$measure}[8],
                     $measure_totals_hash_ref->{$measure}[1], 
                     $mpstat_hash_ref->{$measure}[1],
                     $mpstat_hash_ref->{$measure}[3], 
                     $mpstat_hash_ref->{$measure}[4],
                     $mpstat_hash_ref->{$measure}[5], 
                     $mpstat_hash_ref->{$measure}[6],
                     $mpstat_hash_ref->{$measure}[7], 
                     $mpstat_hash_ref->{$measure}[8],
                     $mpstat_hash_ref->{$measure}[9], 
                     $mpstat_hash_ref->{$measure}[10],
                     $mpstat_hash_ref->{$measure}[11], 
                     $mpstat_hash_ref->{$measure}[12],
                     $mpstat_hash_ref->{$measure}[13], 
                     $measure_totals_hash_ref->{$measure}[9]);
    if(defined($opts{d})){
      push @new_array, ($measure_totals_hash_ref->{$measure}[10], $measure_totals_hash_ref->{$measure}[11], $measure_totals_hash_ref->{$measure}[12]);
    }
    $new_array[5] = $new_array[5]/$new_array[0];
    $measure_totals_hash_ref->{$measure} = \@new_array;
  }
}


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

sub MergeLogs{

  my $proclog = shift;
  my $mpstat = shift;
  my $dtrace = shift;
  my $merged = 'mergedlog';
  my $mergeFH;
  open $mergeFH, ">$merged";
  print "Merging logfiles...\n";
  if(open my $tempFH, "<$proclog"){
    while(my $line = <$tempFH>){
      print $mergeFH $line;
    }
    close $tempFH;
  }
  if(open my $tempFH, "<$mpstat"){
    print $mergeFH "----------------------------------Mpstat_Stats----------------------------------\n";
    while(my $line = <$tempFH>){
      print $mergeFH $line;
    }
    print $mergeFH "END MPSTAT\n";
    close $tempFH;
  }
  if(open my $tempFH, "<$dtrace"){
    print $mergeFH "----------------------------------Dtrace_Stats----------------------------------\n";
     while(my $line = <$tempFH>){
      print $mergeFH $line;
    }
    close $tempFH;
  }
  close $mergeFH;
  return $merged;
}

sub SumDtrace{

  my $pid_hash_ref = shift;
  my $totals_hash_ref = shift;
 
  foreach my $pid (keys %{$pid_hash_ref}){
    foreach my $measure (keys %{$pid_hash_ref->{$pid}}){
      $totals_hash_ref->{$measure}[25] += $pid_hash_ref->{$pid}{$measure}[13];
      $totals_hash_ref->{$measure}[26] += $pid_hash_ref->{$pid}{$measure}[14];
      $totals_hash_ref->{$measure}[27] += $pid_hash_ref->{$pid}{$measure}[15];
    }
  }
}

sub PrintMpstat{

  my $interval = shift;
  my $intervals_run = shift;
  my $mpstat_logfile = shift;

  open my $FH, ">>$mpstat_logfile";

  my $total_CPU = `mpstat $interval 2`;
  my $timestamp = gettimeofday();
  print $FH "MPSTAT,$intervals_run,$timestamp\n$total_CPU";
  close $FH;
}

sub SortProcInfo{

  my $header_array_ref = shift;
  my $proc_hash_ref = shift;
  
  my @header_array = @{$header_array_ref};
  my %proc_hash = %{$proc_hash_ref};

  my %table_hash;
  my %measure_totals_hash;
  my $mintime;

  my $system_time = $header_array[8] - $header_array[10];
  my $CPUcount = $header_array [2];
  my $total_vmem = $header_array[4];
  my $total_pmem = $header_array[6];
  
  print "Sorting proc Data...\n";
  foreach my $pid (keys %proc_hash){
    foreach my $measure (keys %{$proc_hash{$pid}}){
      my ($measure_filler, $boottime, $pid, $cpu_time, $vmem, $pmem, $io_bytes, $name ) = @{$proc_hash{$pid}{$measure}};
      
    
     
      my $cpu_percent;
      my $time_interval;
      my $vmem_percent;
      my $pmem_percent;
      my $io_kb;
      my @stat_array;

      if(defined($proc_hash{$pid}{$measure-1}) && $boottime != -1){

        my $time = $system_time+$boottime;
        my $timestamp = $time;
        $time = sprintf("%.3f", $time);
        $time =~ s/(\d+)(\.\d*)/$1/;
        my $useconds = $2;
        $time = localtime($time);
        $time =~ s/(\d*:\d\d:\d\d)/$1$useconds/;

        $cpu_time = $cpu_time - $proc_hash{$pid}{$measure-1}[3];
        $time_interval = $boottime - $proc_hash{$pid}{$measure-1}[1];

        $cpu_percent = sprintf("%.2f", ((($cpu_time/$time_interval)*100)/$CPUcount));
        $vmem_percent = sprintf("%.2f", $vmem/$total_vmem);
        $pmem_percent = sprintf("%.2f", $pmem/$total_pmem);
        $io_kb = sprintf("%.2f", $io_bytes/1024);

        @stat_array = ($time,$measure,$name,$pid,$timestamp,$time_interval,$cpu_time,
                      $cpu_percent,$vmem,$vmem_percent,$pmem,$pmem_percent,
                      $io_kb);

      }
      else{

        my $time = $header_array[8];
        my $timestamp = $time;
        $time = sprintf("%.3f", $time);
        $time =~ s/(\d+)(\.\d*)/$1/;
        my $useconds = $2;
        $time = localtime($time);
        $time =~ s/(\d*:\d\d:\d\d)/$1$useconds/; 
        @stat_array = ($time,$measure,'proc_failed',$pid,$timestamp,$interval,0,
                      0,0,0,0,0,0);

      }

      if(defined($opts{d})){
        push @stat_array, (0, 0, 0);
      }
   
      if(defined($measure_totals_hash{$measure})){
        if($measure_totals_hash{$measure}[1] > $stat_array[4] && $stat_array[4] != $header_array[8]){
          $measure_totals_hash{$measure}[1] = $stat_array[4]; 
        }
       
        $measure_totals_hash{$measure}[0]++;   
        for my $count (2..9){
          $measure_totals_hash{$measure}[$count] += $stat_array[$count+3];
        }
      }
      else{
        my @totals_array = (1, $stat_array[4], $time_interval, $cpu_time, $cpu_percent,$vmem,$vmem_percent,$pmem,$pmem_percent,$io_kb);
        if(defined($opts{d})){
          push @totals_array, (0, 0, 0);
        }
        $measure_totals_hash{$measure} = \@totals_array;
      }
    
      if(defined($table_hash{$pid})){
        $table_hash{$pid}{$measure} = \@stat_array;
      }
      else{
        my %measure_hash;
        $measure_hash{$measure} = \@stat_array;
        $table_hash{$pid} = \%measure_hash;
      }
    }
  }
  
  my @array = (\%table_hash, \%measure_totals_hash);
  return @array;
}

sub GetHeaderString{

  my $computer = `uname -a`;
  my ($total_vmem, $total_pmem) = get_memory_config();
  my $CPUcount = get_cpu_info();
  my $intervals_run = 0; 
  my $bootime = readcputime($$);
  my $starttime = Mygettimeofday();
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
"$bootime\n";

  return $header_string;
}

sub GetPIDs{

  my $pid_array_ref = shift;
  unless(@ARGV){
    opendir my $dirFH, '/proc/' or die $!;
    @{$pid_array_ref} = readdir $dirFH;
    shift @{$pid_array_ref}; 
    shift @{$pid_array_ref};
    close $dirFH;
  }
  
}


sub ParseDtrace{
  
  my $dtrace_ref = shift;
  my $measure = shift;
  my $period = shift;
  my $pid_measure_ref = shift;
  my @DTRACE = @{$dtrace_ref};

  my $totalio_time = 0;
  my $totalio_size = 0;
  my $totalio_count = 0;
  my %Strategy;
  my %LastDev;
  my %Size;
  my %Count;
  my %Delta;

foreach my $line (@DTRACE) {
  chomp($line);
  next if($line eq '');
  ### Get data
  my ($elapsed,$probe,$size,$dev,$blk,$rest) = split(' ',$line,6);
  
  next if $probe eq "";
  $elapsed = $elapsed / 1_000_000;	# ns -> ms

  #
  #  Store value - the time between I/O events
  #  These are usually the times between,
  # 	strategy -> biodone		# block device
  #
  if ($probe eq "bdev_strategy") {

    my ($pid,$ppid,$uid,$args) = split(' ',$rest,4);

    $Strategy{"$dev:$blk"} = $pid;
    $LastDev{"$dev"} = $elapsed;

		
	} elsif ($probe eq "biodone") {

		if (defined $Strategy{"$dev:$blk"}) {

			my ($vnode,$inode) = split(' ',$rest);

			## $start = $StrategyStart{"$dev:$blk"};
			## $truedelta = $elapsed - $start;
			#
			#  The above lines of code seem obvious, measuring
			#  the time between request and completion - but turns 
			#  out to be a poor estimation of disk I/O. What can 
			#  happen is we have several consecutive requests that
			#  are then serviced by several consecutive 
			#  completions (tagged queueing). By counting the 
			#  deltas between all the requests within the group 
			#  can over-count the actual service time.
			#
			#  What is simple (and would be a "last resort") is
			#  to use the delta time in this event. This works
			#  most of the time - but can give poor results during
			#  simultaneous multiple disk access. Eg, a fast
			#  disk is accessed while a slow disk as accessed - 
			#  the delta on the slow disk completions can often
			#  be the delta to the last fast disk event - recording
			#  smaller than expected times.
			#
			#  Instead of the above we use the delta time between 
			#  this event and the last disk event on the device. 
			#  This gives almost perfect results (we still miss
			#  the small time taken to populate the tagged queue).
			my $truedelta;
			if (defined $LastDev{"$dev"}) {
				$truedelta = $elapsed - $LastDev{"$dev"};
				delete $LastDev{"$dev"};
			} else {
				$truedelta = 0;
			}

			### Fetch who really called this
			my $pid = $Strategy{"$dev:$blk"};

			### Store I/O time
                        $Delta{$pid} += $truedelta;
			$totalio_time += $truedelta;
			
			### Store I/O size
			$Size{$pid} += $size;
			$totalio_size += $size;

			### Store I/O count
			$Count{$pid}++;
			$totalio_count++;

			delete $Strategy{"$dev:$blk"};
			
			
		}
		$LastDev{"$dev"} = $elapsed;
	} 
}

### Prevent divide by zero
$totalio_time = 1000 if $totalio_time == 0;
$totalio_size = 1 if $totalio_size == 0;
$totalio_count = 1 if $totalio_count == 0;


### Cap total I/O time at 100% - either heavy multiple disk access or
### 				 sampling errors (didn't sleep exactly)
my $factor = 1;
$factor = (1000 * $period) / $totalio_time if $totalio_time > (1000 * $period);


foreach my $pid (keys %{$pid_measure_ref}){

  if(defined($Delta{$pid})){
    my $delta = $Delta{$pid};
    my $size = ($Size{$pid}/1024);
    my $count = $Count{$pid};
    my $pcntio_time = $factor * $delta / (10 * $period); #/10 is ms -> %
    $pcntio_time = sprintf("%.2f",$pcntio_time);

    pop @{$pid_measure_ref->{$pid}{$measure}};
    pop @{$pid_measure_ref->{$pid}{$measure}};
    pop @{$pid_measure_ref->{$pid}{$measure}};
    push @{$pid_measure_ref->{$pid}{$measure}}, ($pcntio_time, $size, $count);
  }
}

}


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
  my @mem_array = ($vrtstring, $phystring);

  return @mem_array;
}

sub PrintDtrace{
        
        my $period = shift;
        my $measure = shift;
        my $logfile = shift;
        

	# --- Sanity Check ---
	#
	if (! -r "/dev/mem") {
		die "ERROR1: Sorry, you must be root to run this.\n";
	}

	#
	# --- Generate I/O data from DTrace ---
	#
	open(DTRACE,"dtrace -q -n \"

	   /*
	   **  --- DTrace program to capture I/O ---
	   */

	   /* Initialise sample interval */

	   dtrace:::BEGIN { secs = $period; }
	   profile:::tick-1sec { secs--; }
	   profile:::tick-1sec /secs == 0/ { exit(0); }

	   /* Fetch disk block activity */
	
	   fbt:genunix:bdev_strategy:entry
	   {
		bufp = (buf_t *)arg0;
	
		printf(\\\"%d %s %d %d %d %d %d %d %s\\n\\\",
		 timestamp,probefunc,bufp->b_bcount,bufp->b_edev,
		 bufp->_b_blkno._f,pid,curpsinfo->pr_ppid,
		 curpsinfo->pr_euid,curpsinfo->pr_psargs);
	   }

	   fbt:genunix:biodone:entry
	   {
		bufp = (buf_t *)arg0;
		pagep = (page_t *)bufp->b_pages;
		vnodep = (int)pagep == 0 ? 0 : (vnode_t *)pagep->p_vnode;
		vnode =  (int)vnodep == 0 ? 0 : (int)vnodep;
		inodep = (int)vnodep == 0 ? 0 : (inode_t *)vnodep->v_data;
		inode =  (int)inodep == 0 ? 0 : inodep->i_number;
	
		printf(\\\"%d %s %d %d %d %x %d\\n\\\",
		 timestamp,probefunc,bufp->b_bcount,bufp->b_edev,
		 bufp->_b_blkno._f,vnode,inode);
	   }

	\" |") || die "ERROR2: Can't run dtrace: $!\n is this Solaris 10?\n";

	my @DTRACE = <DTRACE>;
        
	close DTRACE;
        
        open my $FH, ">>$logfile";
        my $timestamp = gettimeofday();
        print $FH "DTRACE,$measure,$timestamp\n";
        print $FH @DTRACE;
        print $FH "END DTRACE MEASURE\n";
        close $FH;
        
}





sub Mygettimeofday{
  my ($sec,$usec) = gettimeofday();
  my $time = "$sec\.$usec";
  return $time;
}




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
  my $interval = $opts_hash_ref->{i};
  my $runs = $opts_hash_ref->{r};

  # check that the logfile is valid and open it
  # and create a FH for it
 

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
  $opts_hash_ref->{l} = $logfile;
  $opts_hash_ref->{i} = $interval;
  $opts_hash_ref->{r} = $runs;
 
}

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

sub ReadProcFile{
	
  my $pid = shift;
  my $USAGE;
  my $PSINFO;
  my %proc_data;

  # attempt to read 256 bytes from the pid psinfo file	
  if(open($PSINFO,"/proc/$pid/psinfo")){
    read($PSINFO, $proc_data{psinfo}, 256);
    close($PSINFO);
  }
  else{
    $proc_data{psinfo} = -1;
  }

  # attempt to read 256 bytes from the pid usage file
  if(open($USAGE,"/proc/$pid/usage")){
    read($USAGE, $proc_data{usage}, 256);
    close($USAGE);
  }
  #failed to read the file
  else{
    $proc_data{usage} = -1;	
  }

  return \%proc_data;
}

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
    my $time = timestruct2int($pr_tstamp);
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
