#!/usr/bin/perl
use strict;
use warnings;

# rscript.pl:
#     A rotating backup script for linux systems.
# This script is meant to be run as a daily cron job with output directed to a log file. eg:
#      30 2 * * * [path to]/rscript.pl &> [log file]
# Essentially, it will make a specified number of daily backups. When the oldest backup falls on a 
# specified day of the week, it will be moved to the weekly directory instead of being deleted. Likewise,
# the oldest weekly backup will be moved to the monthly folder under specified circumstances. 
# 
# All backups are made by rsync with the --link-dest option, so that each backup directory contains
# a full backup, but they only take up the disk space of a single copy (plus changes).
#

print "Starting to run the backup script.\n";

use File::Path qw( make_path remove_tree );
use File::Copy qw(move);
use Date::Day;

my $maxDays = 4;
my $maxWeeks = 4;
my $maxMonths = 1;

# all the following directories need trailing slashes
my $srcDir = "/u12/";          # needs a leading slash
my $bRoot = "/home/backups/spike_u12/";     # needs a leading slash
my $daily = "nightlies/";
my $weekly = "weeklies/";
my $monthly = "monthlies/";
my $dayinweek = "MON";
my $dayinmonth = 7;   #If the day of the month is before this number, the backup will be a candidate for a Monthly
                       # (use 7 to get a monthly from the first week of the month)
my $filebase = "u12.";
my $current = "current";


# make print commands end with a newline
$\ = "\n";


my $startstamp = "/home/backups/tools/start";
my $finishstamp = "/home/backups/tools/finish";

#timestamp for process start
system("touch $startstamp") == 0
                 or die "system touch $startstamp failed: $?";


# First, lets clean up the Backup directories:
#############################################
print "Cleaning the directory of old backups...";

# beginning with the Daily directory:
#############
{
	my $wDir = $bRoot.$daily;
	opendir (my $dh, $wDir) or die "can't opendir $wDir: $!";
	my @files = readdir($dh);
	@files = sort @files;
	# remove the . and .. entries
	@files = reverse @files[2..$#files];
	until (@files < $maxDays) {  # There needs to be room for the one we will make
		$files[$#files] =~ /\.(\d+)-(\d+)-(\d+)\./;
		my $year = $1;
		my $month = $2;
		my $day = $3;
		print "Extra backup found for $month-$day-$year in the Daily directory";
		my $dayname = day($month,$day,$year);
		print "Weekly backups come from $dayinweek and this is a $dayname";
		if ($dayname eq $dayinweek) {
			print "moving $wDir$files[$#files] to $bRoot$weekly$files[$#files]";
			move($wDir.$files[$#files],$bRoot.$weekly.$files[$#files]) 
						or die "can't move file $files[$#files]: $!";
		}
		else {
			print "removing $wDir$files[$#files]";
			remove_tree( $wDir.$files[$#files] ) or die "can't delete file $files[$#files]: $!";
		}
	
		@files = @files[0..($#files-1)];
	}
}

# Now the Weekly directory
###########
{
	my $wDir = $bRoot.$weekly;
	opendir (my $dh, $wDir) or die "can't opendir $wDir: $!";
	my @files = readdir($dh);
	@files = sort @files;
	# remove the . and .. entries
	@files = reverse @files[2..$#files];
	until (@files <= $maxWeeks) {
		$files[$#files] =~ /\.(\d+)-(\d+)-(\d+)\./;
		my $year = $1;
		my $month = $2;
		my $day = $3;
		print "Extra backup found for $month-$day-$year in the Weekly directory";
		print "Monthly backups come from days earlier than the $dayinmonth and this is a $day";
		if ($day <= $dayinmonth) {
			print "moving $wDir$files[$#files] to $bRoot$monthly$files[$#files]";
			move($wDir.$files[$#files],$bRoot.$monthly.$files[$#files]) 
						or die "can't move file $files[$#files]: $!";
		}
		else {
			print "removing $wDir$files[$#files]";
			remove_tree( $wDir.$files[$#files] ) or die "can't delete file $files[$#files]: $!";
		}
	
		@files = @files[0..($#files-1)];
	}
}

# Now the Monthly directory
###########
{
	my $wDir = $bRoot.$monthly;
	opendir (my $dh, $wDir) or die "can't opendir $wDir: $!";
	my @files = readdir($dh);
	@files = sort @files;
	# remove the . and .. entries
	@files = reverse @files[2..$#files];
	until (@files <= $maxMonths) {
		$files[$#files] =~ /\.(\d+)-(\d+)-(\d+)\./;
		my $year = $1;
		my $month = $2;
		my $day = $3;
		print "Extra backup found for $month-$day-$year in the Monthly directory";
			
		print "removing $wDir$files[$#files]";
		remove_tree( $wDir.$files[$#files] ) or die "can't delete file $files[$#files]: $!";
			
		@files = @files[0..($#files-1)];
	}
}

print "Finished with cleanup.\n";


# Find out what the date is:
#############################
my $date;
# open a file handle, pipe it in, call date, with argument _
open(DATE, "-|", 'date', "+%Y-%m-%d.%H-%M-%S" ) or die "can't open date: $!";
# place the results in $date
chomp($date = <DATE>);
close DATE;
print "The date is $date";



my $bDir = $bRoot.$daily.$filebase.$date;
print "Backup will be made to $bDir";
# make_path returns undef if directory already exsists
#  so I can't do an 'or die'.
#  critical errors will kill the program anyway
make_path($bDir);

my $bCurrent = $bRoot.$filebase.$current;

print "Beginning backup...";
# This command does the backup operation. 
# rsync options:
#   -a  maintain file permissions, ownership, timestamps
#   -H  maintain Hardlinks
#   -x  do not recurse into mounted file systems
#   -W  whole files, do not do hash checking (since we have a fast connection, 
#                                        it is not worth the processing overhead)
#   -numeric-ids  do not transalte permission id #s into names.
#   --delete      remove files that are no longer in the souce
#   --link-dest   if the file to be backed up already exists in the link-dest 
#                      directory, just create a hard link rather than backing it up again.
system("rsync -aHxW --numeric-ids --delete --link-dest=$bCurrent $srcDir $bDir") == 0
		or die "system rsync $srcDir $bDir failed: $?";

print "Rsync complete.";

# provide an accurate timestamp on the folder of when the backup was done
system("touch $bDir") == 0
		or die "system touch $bDir failed: $?";

# update the Current backup softlink to the most recent backup
remove_tree($bCurrent);
system("ln -s $bDir $bCurrent") == 0
		or die "system ln -s $bDir $bCurrent failed: $?";

# time stamp for process end
system("touch $finishstamp") == 0
                or die "system touch $finishstamp failed: $?";

print "Goodbye!";

