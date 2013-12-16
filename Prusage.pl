#!/usr/bin/perl
#
# prusage - Process usage stats, Solaris. I/O, sys/usr times, context switches.
#           A supplement to "ps", can be run as any user.
#
# 01-Jul-2005, ver 1.00  (check for newer vers, http://www.brendangregg.com)
#
#
# USAGE: prusage [-bchinuwxCT] [-p PID] [-s sort] [-t top] [interval] [count]
#  
#      prusage               # Default. (-ic 1), fit to screen, 1 secs.
#      prusage -b            # Child times report (must be root or owner)
#      prusage -i            # I/O stats (default)
#      prusage -u            # USR/SYS times
#      prusage -x            # Context Switchs
#      prusage -w            # Wide output
#      prusage -c            # Clear the screen (default)
#      prusage -C            # Don't clear the screen
#      prusage -T            # Don't fit to screen (print all lines)
#      prusage -p pid        # Print this PID only
#      prusage -s sort       # Sort on pid,blks,cpu,utime,inblk,vctx,...
#      prusage -t lines      # Print top lines only
#  eg,
#      prusage 2             # 2 second samples (first is historical)
#      prusage 2 5           # 5 x 2 second samples 
#      prusage -xi 2         # I/O and Context switch reports, 2 secs
#      prusage -biux 10      # multi output, all reports every 10 secs
#      prusage -C 10         # 10 second samples, no clear screen
#      prusage -CT 10        # 10 second samples, all lines
#      prusage -Ct8 10 5     # 5 x 10 second samples, top 8 lines only
#      prusage -p 11321      # PID 11321 only
#      prusage -s pid        # sort on PID 
#
# FIELDS:
#		PID	Process ID
#		MINF	Minor Page Faults (satisfied from RAM)
#		MAJF	Major Page Faults (satisfied by disk I/O)
#		INBLK	In Blocks (disk I/O reads)
#		OUBLK	Out Blocks (disk I/O writes)
#		CHAR-kb	Character I/O Kbytes
#		COMM	Command name
#		USR	User Time
#		SYS 	System Time
#		CUSR	Child User Time
#		CSYS 	Child System Time
#		WAIT	Wait for CPU Time
#		LOCK	User waiting on lock time
#		TRAP	System trap time
#		VCTX	Voluntary Context Switches (I/O bound)
#		ICTX	Involuntary Context Switches (CPU bound)
#		SYSC	System calls
#
# NOTE: Minor faults always report zero on most versions of Solaris.
#
# REFERENCE: /usr/include/sys/procfs.h
#
# SEE ALSO: psio				# process I/O
#	    prstat -m				# USR/SYS times, ...
#           /usr/ucb/rusage			# historical
#
# COPYRIGHT: Copyright (c) 2004, 2005 Brendan Gregg.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#  (http://www.gnu.org/copyleft/gpl.html)
#
# Author: Brendan Gregg  [Sydney, Australia]
#
# 31-Aug-2004	Brendan Gregg	Created this.
# 12-Mar-2005	   "      " 	Processed /proc/*/psinfo as well.
# 09-May-2005	   "      " 	Processed /proc/*/usage as well.

use Getopt::Std;

#
# --- Default Variables ---
#
$INTERVAL = 1;		# seconds to sample
$MAX = 2**32;		# max count of samples
$NEW = 0;		# skip summary output (new data only)
$WIDE = 0;		# print wide output (don't truncate)
$SCHED = 0;		# print PID 0
$TOP = 0;		# print top many only
$FIT = 1;		# fit to screen
$CLEAR = 1;		# clear screen before outputs
$STYLE_IO = 1;		# default output style, I/O
$STYLE_CTX = 0;		# output style, Context Switches
$STYLE_TIME = 0;	# output style, Times
$STYLE_CHILD = 0;	# output style, Child times
$MULTI = 0;		# multi reports, multiple styles
$TARGET_PID = -1;	# target PID, -1 means all
$count = 1;		# current iteration

#
# --- Command Line Arguments ---
#

### Check usage
&Usage() if $ARGV[0] eq "--help";
getopts('bchinuwxp:s:t:CT') || &Usage();
&Usage() if $opt_h;

### Process options
$NEW = 1 if $opt_n;
$WIDE = 1 if $opt_w;
$FIT = 0 if $opt_T;
$CLEAR = 0 if $opt_C;
$STYLE_IO = 0 if $opt_x || $opt_u || $opt_b;
$STYLE_CTX = 1 if $opt_x;
$STYLE_TIME = 1 if $opt_u;
$STYLE_CHILD = 1 if $opt_b;
$STYLE_IO = 1 if $opt_i;
$TOP = $opt_t if defined $opt_t;
$SORT = $opt_s if defined $opt_s;
$TARGET_PID = $opt_p if defined $opt_p;
$INTERVAL = shift(@ARGV) || $INTERVAL;
$MAX = shift(@ARGV) || $MAX;

### Determine style count
$STYLES = $STYLE_IO + $STYLE_CTX + $STYLE_TIME + $STYLE_CHILD;
$MULTI = 1 if $STYLES > 1;

### Determine clear seq
$CLEARSTR = `clear` if $CLEAR;

### Fit to screen
if ($FIT && ! $opt_t) {
	my ($row,$col) = &getwinsz();
	$TOP = int(($row - $STYLES * 2) / $STYLES);
} 


#
# --- Main ---
#
for (;$count <= $MAX; $count++) {

	### Get data
	&GetProcStat();		# fetch and save /proc stats in %PID{$pid}

	next if $NEW && $count == 1;

	### Print data
	print $CLEARSTR if $CLEAR;
	&PrintIO($SORT) if $STYLE_IO;
	&PrintCtx($SORT) if $STYLE_CTX;
	&PrintTime($SORT) if $STYLE_TIME;
	&PrintChild($SORT) if $STYLE_CHILD;
	
	### Pause
	sleep($INTERVAL) unless $count == $MAX;

	### Cleanup memory
	undef %PID;
	undef %Comm;
}


#
# --- Subroutines ---
#

# GetProcStat - Gets /proc usage statistics and saves them in %PID.
#	This can be run multiple times, the first time %PID will be 
#	populated with the summary since boot values.
#	This reads /proc/*/usage and /proc/*/psinfo.
#
sub GetProcStat {
   my $pid;
   chdir "/proc";

   foreach $pid (sort {$a<=>$b} <*>) {
	next if $pid == $$;
	next if $pid == 0 && $SCHED == 0;
	next if $TARGET_PID > -1 && $pid != $TARGET_PID;
	
	#
	#  struct prusage 
	#

	### Read usage stats
	open(USAGE,"/proc/$pid/usage") || next;
	read(USAGE,$usage,256);
	close USAGE;
	
	### Unpack usage values
	($pr_lwpid, $pr_count, $pr_tstamp, $pr_create, $pr_term, 
	 $pr_rtime, $pr_utime, $pr_stime, $pr_ttime, $pr_tftime, 
	 $pr_dftime, $pr_kftime, $pr_ltime, $pr_slptime, $pr_wtime, 
	 $pr_stoptime, $filltime, $pr_minf, $pr_majf, $pr_nswap, 
	 $pr_inblk, $pr_oublk, $pr_msnd, $pr_mrcv, $pr_sigs, 
	 $pr_vctx, $pr_ictx, $pr_sysc, $pr_ioch, $filler) = 
	 unpack("iia8a8a8a8a8a8a8a8a8a8a8a8a8a8a48LLLLLLLLLLLLa40",$usage);

	### Process usage values
	$New{$pid}{utime} = timestruct2int($pr_utime);
	$New{$pid}{stime} = timestruct2int($pr_stime);
	$New{$pid}{ttime} = timestruct2int($pr_ttime);
	$New{$pid}{ltime} = timestruct2int($pr_ltime);
	$New{$pid}{wtime} = timestruct2int($pr_wtime);
	$New{$pid}{slptime} = timestruct2int($pr_slptime);
	$New{$pid}{minf}  = $pr_minf;
	$New{$pid}{majf}  = $pr_majf;
	$New{$pid}{nswap} = $pr_nswap;
	$New{$pid}{inblk} = $pr_inblk;
	$New{$pid}{oublk} = $pr_oublk;
	$New{$pid}{vctx}  = $pr_vctx;
	$New{$pid}{ictx}  = $pr_ictx;
	$New{$pid}{sysc}  = $pr_sysc;
	$New{$pid}{ioch}  = $pr_ioch;
	# and a couple of my own,
	$New{$pid}{blks}  = $pr_inblk + $pr_oublk;
	$New{$pid}{ctxs}  = $pr_vctx + $pr_ictx;
	$New{$pid}{cpu}  = $New{$pid}{utime} + $New{$pid}{stime};

	#
	#  struct psinfo
	#

	### Read psinfo stats
	open(PSINFO,"/proc/$pid/psinfo") || next;
	read(PSINFO,$psinfo,256);
	close PSINFO;

	### Unpack psinfo values
	($pr_flag, $pr_nlwp, $pr_pid, $pr_ppid, $pr_pgid, $pr_sid,
	 $pr_uid, $pr_euid, $pr_gid, $pr_egid, $pr_addr, $pr_size,
	 $pr_rssize, $pr_pad1, $pr_ttydev, $pr_pctcpu, $pr_pctmem,
	 $pr_start, $pr_time, $pr_ctime, $pr_fname, $pr_psargs,
	 $pr_wstat, $pr_argc, $pr_argv, $pr_envp, $pr_dmodel,
	 $pr_taskid, $pr_projid, $pr_nzomb, $filler) =
	 unpack("iiiiiiiiiiIiiiiSSa8a8a8Z16Z80iiIIaa3iiia",$psinfo);

        ### Save command name
        $Comm{$pid} = $pr_fname;

	next unless $STYLE_CHILD;	# only child needs the following,

	#
	#  struct pstatus
	#

	### Read pstatus stats
	open(PSTATUS,"/proc/$pid/status") || next;
	read(PSTATUS,$pstatus,128);
	close PSTATUS;

	### Unpack pstatus values
	($pr_flags, $pr_nlwp, $pr_pid, $pr_ppid, $pr_pgid, $pr_sid,
	 $pr_aslwpid, $pr_agentid, $pr_sigpend, $pr_brkbase, $pr_brksize, 
	 $pr_stkbase, $pr_stksize, $pr_utime, $pr_stime, $pr_cutime,
	 $pr_cstime, $filler) =
	 unpack("iiiiiiiia16iiiia8a8a8a8a",$pstatus);

	### Process pstatus values
	$New{$pid}{cutime} = timestruct2int($pr_cutime);
	$New{$pid}{cstime} = timestruct2int($pr_cstime);
	$New{$pid}{ccpu}  = $New{$pid}{cutime} + $New{$pid}{cstime};
   }

   ### Cleanup memory
   foreach $pid (keys %New) {
	# save PID values,
	foreach $key (keys %{$New{$pid}}) {
		$PID{$pid}{$key} = $New{$pid}{$key} - $Old{$pid}{$key};
	}
   }
   undef %Old;
   foreach $pid (keys %New) {
	# save old values,
	foreach $key (keys %{$New{$pid}}) {
		$Old{$pid}{$key} = $New{$pid}{$key};
	}
   }
}

# PrintIO - print a report on I/O statistics: minf, majf, inblk, oublk, ioch.
#
sub PrintIO {
	my $sort = shift || "blks";
	my $top = $TOP;
	my $pid;
   
	### Print header
	printf("%6s %5s %5s %8s %8s %9s %s\n","PID",
	 "MINF","MAJF","INBLK","OUBLK","CHAR-kb","COMM");
 
	### Print report
	foreach $pid (&SortPID("$sort")) {
		printf("%6s %5s %5s %8s %8s %9.0f %s\n",$pid,
		 $PID{$pid}{minf},$PID{$pid}{majf},$PID{$pid}{inblk},
		 $PID{$pid}{oublk},$PID{$pid}{ioch}/1024,
		 trunc($Comm{$pid},33));
		last if --$top == 0;
	}
	print "\n" if $MULTI;
}

# PrintTime - print a report on Times: utime, stime, wtime, ltime, ttime.
#
sub PrintTime {
	my $sort = shift || "cpu";
	my $top = $TOP;
	my $pid;
   
	### Print header
	printf("%6s %8s %8s %8s %6s %6s %s\n","PID",
	 "USR","SYS","WAIT","LOCK","TRAP","COMM");
 
	### Print report
	foreach $pid (&SortPID("$sort")) {
		printf("%6s %8.2f %8.2f %8.2f %6.2f %6.2f %s\n",$pid,
		 $PID{$pid}{utime},$PID{$pid}{stime},$PID{$pid}{wtime},
		 $PID{$pid}{ltime},$PID{$pid}{ttime},trunc($Comm{$pid},32));
		last if --$top == 0;
	}
	print "\n" if $MULTI;
}

# PrintCtx - print a report on Context Swithes: utime, stime, vctx, ictx, sysc.
#
sub PrintCtx {
	my $sort = shift || "ctxs";
	my $top = $TOP;
	my $pid;
   
	### Print header
	printf("%6s %7s %7s %9s %8s %10s %s\n","PID",
	 "USR","SYS","VCTX","ICTX","SYSC","COMM");
 
	### Print report
	foreach $pid (&SortPID("$sort")) {
		printf("%6s %7.2f %7.2f %9s %8s %10s %s\n",$pid,
		 $PID{$pid}{utime},$PID{$pid}{stime},$PID{$pid}{vctx},
		 $PID{$pid}{ictx},$PID{$pid}{sysc},trunc($Comm{$pid},27));
		last if --$top == 0;
	}
	print "\n" if $MULTI;
}

# PrintChild - print a report on Times: utime, stime, wtime, ltime, ttime.
#
sub PrintChild {
	my $sort = shift || "ccpu";
	my $top = $TOP;
	my $pid;
   
	### Print header
	printf("%6s %8s %8s %8s %8s %s\n","PID",
	 "USR","SYS","CUSR","CSYS","COMM");
 
	### Print report
	foreach $pid (&SortPID("$sort")) {
		printf("%6s %8.2f %8.2f %8.2f %8.2f %s\n",$pid,
		 $PID{$pid}{utime},$PID{$pid}{stime},$PID{$pid}{cutime},
		 $PID{$pid}{cstime},trunc($Comm{$pid},32));
		last if --$top == 0;
	}
	print "\n" if $MULTI;
}

# SortPID - sorts the PID hash by the key given as arg1, returning a sorted
#	array of PIDs.
#
sub SortPID {
	my $sort = shift;
	
	### Sort numerically
	if ($sort eq "pid") {
   		return sort {$a <=> $b} (keys %PID);
	} else {
   		return sort {$PID{$b}{$sort} <=> $PID{$a}{$sort}} (keys %PID);
	}
}

# getwinsz - gets the terminal window size and returns it as x, y.
#	The default size returned is 24x80 if an error is encountered.
#
sub getwinsz {
	my $row = 24;
	my $col = 80;
	my ($xpix,$ypix,$winsize);
	my $TIOCGWINSZ = 21608;         # check /usr/include/sys/termios.h
 
	open(TTY, "+</dev/tty") || return($row,$col);
	ioctl(TTY, $TIOCGWINSZ, $winsize='') || return($row,$col);
	($row, $col, $xpix, $ypix) = unpack('S4', $winsize);
	return($row,$col);
}

# timestruct2int - Convert a timestruct value (64 bits) into an integer
#	of seconds.
#
sub timestruct2int {
	my $timestruct = shift;
	my ($secs,$nsecs,$time);
 
	$secs = $nsecs = $time = 0;
	($secs,$nsecs) = unpack("LL",$timestruct);
	$time = $secs + $nsecs * 10**-9;
	return $time;
}

# trunc - Returns a truncated string if required.
#
sub trunc {
	my $string = shift;
	my $length = shift;

	if ($WIDE) {
		return $string;
	} else {
		return substr($string,0,$length);
	}
}

# Usage - print usage message and exit.
#
sub Usage {
	print STDERR <<END;
prusage ver 0.97
USAGE: prusage [-chinuwx] [-p PID] [-s sort] [-t top] [interval] [count]
 
      prusage               # Default. (-ic 1), fit to screen, 1 secs.
      prusage -b            # Child times report (must be root or owner)
      prusage -i            # I/O stats (default)
      prusage -u            # USR/SYS times
      prusage -x            # Context Switchs
      prusage -w            # Wide output
      prusage -c            # Clear the screen (default)
      prusage -C            # Don't clear the screen
      prusage -T            # Don't fit to screen (print all lines)
      prusage -p pid        # Print this PID only
      prusage -s sort       # Sort on pid,blks,cpu,utime,inblk,vctx,...
      prusage -t lines      # Print top lines only
   eg,
      prusage 2             # 2 second samples (first is historical)
      prusage 2 5           # 5 x 2 second samples 
      prusage -xi 2         # I/O and Context switch reports, 2 secs
      prusage -biux 10      # multi output, all reports every 10 secs
      prusage -C 10         # 10 second samples, no clear screen
      prusage -CT 10        # 10 second samples, all lines
      prusage -Ct8 10 5     # 5 x 10 second samples, top 8 lines only
      prusage -p 11321      # PID 11321 only
      prusage -s pid        # sort on PID 
END
	exit;
}
