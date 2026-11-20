#!/usr/bin/env perl
use strict;
use warnings;
use List::Util qw(shuffle);
use Fcntl qw(:flock);

# Ensure only one instance of this script runs at a time
open(my $self, '<', $0) or die "Cannot open script file: $!";
flock($self, LOCK_EX | LOCK_NB) or exit(0); # Exit silently if already running

my $interval = 240;
my $wallpaper_dir = "$ENV{HOME}/Pictures/Wallpaper";

# Trap SIGUSR1 to interrupt sleep and immediately skip to the next wallpaper
$SIG{USR1} = sub { print "Skipping to next wallpaper...\n"; };

while (1) {
   # Ensure awww-daemon is running and responsive
    if (system("awww query > /dev/null 2>&1") != 0) {
            system("awww-daemon &");
            sleep(1);
    }

    my @files = shuffle(glob("$wallpaper_dir/*"));

    unless (@files) {
        warn "No wallpapers found in $wallpaper_dir\n";
        sleep($interval);
        next;
    }

    for my $file (@files) {
        next unless -f $file;
        print "Setting: $file\n";

        my $rc = system {
            "awww"
        } "awww", "img", $file, "--transition-type", "fade", "--transition-step", "90";

        if ($rc == -1) {
            warn "Failed to execute awww: $!";
        }
        elsif ($rc != 0) {
            warn "awww exited with status " . ($rc >> 8);
        }
        sleep($interval);
    }
}
