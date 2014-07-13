ProcMonitor
===========
This small script records information from the proc directory and calculates 
statistics for the Solaris 5.10 Operating System. It was written to be run 
Out-of-the-Box with a fresh install of Solaris 5.10 Update 11. It uses as 
little processing as possible and offsets its processing time from it 
calculations. The script is pretty accurate down to measurement intervals of 
0.1 seconds. The script outputs statistics for each process and totals 
everything into a new directory on each run. The output is in the form of 
comma separated values. 

To run the script, enter this in the terminal:
<pre><code># perl ProcMonitor.pl
</code></pre>
To see usage details and info:
<pre><code># perl ProcMonitor.pl -h
</code></pre>
Below is the usage output:
<pre><code>#########################################################################
    ProcMonitor.pl usage and manual.

ProcMonitor.pl monitors CPU and memory attributes over a time
interval for Solaris 5.10. Each interval takes a snapshot
measurement which can then be used to make observations
and calculations such as averages. The output format and
options are described below. Pressing the Conrtol-C will
end the monitor process, and began the post processing.

ProcMonitor.pl will read and record /proc filesystem stats
for each pid. After the recording period is over, post
processing will be done, and output files will be recorded
into a directory passed by the -d option, or a default
directory explained below. The files will be generated for
each process including averages and totals. The files will
all be in a Comma Seperated Value (CSV) format. Read below
for a detailed description of each of the columns.

#########################################################################
Options:
-a running_average: This is the amount of time in seconds
  that the running average should be taken over. The default
  is 10 seconds.\n".
-i interval: This is the time the interval should try to run
  over in seconds. The interval will be increased under
  high CPU and process load. The default is 1 second.
-r runs: A certain number of measures to take. The default is
  to run indefinetly till control-C is pressed.
-d directory: This is the directory to create the stat data files
  in. The default will be a directory created in the pwd with
  a generic name as in e.g. ProcMonitor_MM_DD_YYYY_testX.
-h: Print out this manual.

#########################################################################
PID stat file columns in order:
'DATETIME': This column is a timestamp of the exact
  time the record was taken. It is the following
  format: Weekday Month Day Hours:Min:Sec:uSec Year,
  e.g. $time
'MEASURE': The current measurement interval this was taken on.
'PROCESSNAME': The name of the executed file.
'PID': The PID number of the process.
'TIMESTAMP': A numerical precise timestamp in seconds since
  the beginning of the epoch.
'INTERVAL': The interval in seconds that this measurement
  was made over.
'PROCESSTIME': The amount of processor time in seconds the
  the process recieved over the time interval.
'CPU%': The calculated CPU utilization over the time period.
'VMEM(kB)': The size of the virtual memory this process holds.
'VMEM%': The percent of virtual memory out of total system
  virtual memory.
'PMEM(kB)': The size of the physical memory this process holds.
'PMEM%': The percent of physical memory out of total system
  physical memory.
'IO(kB)': The amount of chars read or written by the process
  over the time interval. This is not nessarily disk
  writes or reads.

#########################################################################
Total file columns in order:
'MEASURE': The current measure for this total.
'PIDCOUNT': The total number of pids found during the interval.
'STARTTIME': The time the first process was recorded for this
  interval.
'AVGINTERVAL': The average interval for all PIDs during this
  measure
'PROCESSTIME': The total processor time for all PIDs during
  this measure
'CPU%': Total CPU utilization during this measure.
'VMEM(kB)': Total virtual memory used at the end of this measure.
'VMEM%': Perecnt of total virtual memory used at the end of this
  measure.
'PMEM(kB)': Total physical memory used at the end of this measure.
'PMEM%': Perecnt of total physical memory used at the end of this
  measure.
'IO(kB)': Total chars read or written during this measure.

#########################################################################
Written by Daniel Moody, dmoody256@gmail.com
</code></pre>
