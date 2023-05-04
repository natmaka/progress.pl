#!/usr/bin/perl
use strict;
use warnings;
use Modern::Perl '2010';
use utf8;
use v5.20;

use POSIX ':sys_wait_h';
use Fcntl ':mode';
use Time::HiRes;

my $start = Time::HiRes::time();

my ($child, $running, $exit);

if (not $#ARGV and $ARGV[0] =~ /^\d+/) {
  $child = 1*$ARGV[0];
  $running = sub { kill(0, $child) > 0 };
  $exit = sub { exit 0; };

	open(my $DATA, '<', '/proc/self/stat') or die 'Cannot open /proc/self/stat';
  my @s = split(' ', <$DATA>);
  close $DATA or die 'Cannot use /proc/self/stat';
  my $hznow = 0+$s[21];
  my $hertz = POSIX::sysconf(POSIX::_SC_CLK_TCK());

	open(my $fh_chld, '<', "/proc/$child/stat") or die "Cannot open /proc/$child/stat $!";
  @s = split(' ', <$fh_chld>);
  close $fh_chld or die "Cannot use /proc/$child/stat";
  $start -= ($hznow - $s[21])*1.0/$hertz;
} else {
  $child = fork();
  if (defined($child) and not $child) {
    exec(@ARGV);
  }
  $running = sub { waitpid($child, WNOHANG) == 0; };
  $exit = sub {
    my $code = $?;
    my $sig = $? & 127;
    my $core = $? & 128;
    my $status = $? >> 8;
    if ($? & 127) {
      die "progress.pl: Child died by signal $sig".($core ? "( core dumped)":"")."\n";
    } else {
      exit $status;
    }
  };
}


sub prettytime {
  my $t = shift;
  if ($t >= 3600) {
    $t += 59.99;
    return int($t/3600)."h ".int(($t % 3600)/60)."m";
  } elsif ($t >= 60) {
    $t += 0.99;
    return int($t/60)."m ".int($t % 60)."s";
  } else  {
    return int($t+0.99)."s";
  }
}
Time::HiRes::sleep 0.1;
my @lines;
my $size=-1;
my $buf=-1;
my $previous_size=-1;
my $previous_buf=-1;
while ($running->()) {
  my @f = glob "/proc/$child/fd/*";
  my @lengths = map { length($_) } @lines;
  @lines = ();
  my $now = Time::HiRes::time();
  my $duration = $now - $start;
	my $DATA;
	map {
    my $l = readlink $_;
    my @s = stat $l;
    $size = -1;
		if (defined $s[2]) {
			if (S_ISREG($s[2])) {
				s/fd/fdinfo/;
				$size = $s[7];
			} elsif (S_ISBLK($s[2])) {
				s/fd/fdinfo/;
				if (substr($l,0,5) == '/dev/') {
					local $_;
					open($DATA, '<', '/proc/partitions') or die 'Cannot open /proc/partitions';
					while (<$DATA>) {
						my @l = split;
						if ($l[0] == ($s[6] >> 8) and $l[1] == ($s[6]%256)) {
							$size = $l[2]*1024;
						}
	  }
	}
	close $DATA or die 'Cannot use /proc/partitions';
      }
    }
    if ($size >= 0) {
      open(my $DATA, '<', $_) or die "Cannot open $_";
      sysread($DATA, $buf, 4096);
      close $DATA or die "Cannot use $_";
      #warn "$buf $l $s[2] --debug--";
      if ( $buf =~ /^pos:\s*(\d+)\s+flags:\s*(\S+)\s/s ) {
	my ($p, $f) = ($1, $2);
	my ($pp, $eta);
	if ($size and $p) {
	  $pp = $size ? sprintf("%5.1f", $p*100.0/$size) : " --.-";
	  my $totaltime = $duration * $size / $p;
	  $eta = "in ".prettytime($totaltime - $duration)." of ".prettytime($totaltime);
	} else {
	  $pp = " --.-";
	  $eta = '-';
	}
	push @lines, "$pp% | $p of $size | $eta | $f | $l";
      }
    }
  } @f;
	if (($size ne $previous_size) or ($previous_buf ne $buf)) {
		print STDERR map { "\e[A" } @lengths;
		for (my $i=0; $i <= $#lines or $i <= $#lengths; $i++) {
		next if ( (!defined $lines[$i]) or (!defined $lengths[$i]));
    printf STDERR "%-*s\n", $lengths[$i], $lines[$i];
  }
}
  Time::HiRes::sleep 0.5;
}
$exit->();
