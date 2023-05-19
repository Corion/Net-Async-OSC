#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp 'croak';

use Protocol::OSC;
use IO::Async::Loop;
use IO::Async::Socket;
use IO::Async::Timer::Periodic;
use Socket 'pack_sockaddr_in', 'inet_aton'; # IPv6 support?!

my $osc = Protocol::OSC->new;

sub new_socket( $loop, $host, $port ) {
    my $pingback = IO::Async::Socket->new(
        on_recv => sub( $sock, $data, $addr, @rest ) {
            warn "Reply: $data";
        },
        #on_recv_error => sub {
        #   my ( $self, $errno ) = @_;
        #   warn "Cannot recv - $errno\n";
        #},
    );
    $loop->add( $pingback );
    # What about multihomed hosts?!
    $pingback->connect(
        host => $host,
        service => $port,
        socktype => 'dgram'
    )->get;
    return $pingback
}

sub send_osc( $socket, @message ) {
    my $data = $osc->message(@message); # pack
    send_osc_msg( $socket, $data );
}

sub send_osc_msg( $socket, $data ) {
    say join " , " , @{ $osc->parse( $data ) };
    $socket->send( $data );
}

my $loop = IO::Async::Loop->new();
my $udp = new_socket($loop, '127.0.0.1', 4560);

my $bpm = 120;
my $beats = 4; # 4/4
my $ticks = 4; # ticks per beat, means 1/16th notes
my $tracks = 4; # so far...

sub loc($tick, $track) {
    $tick*$tracks+$track
}

sub beat($beat, $track) {
    return loc($ticks*$beat,$track)
}

my $sequencer = [];

# We don't only want full programmatic stuff, we also want
# to specify stuff via patterns, just like in any sequencer.
# Most likely we want to parse (drum) patterns like:
#
# HH|x-x-x-x-x-x-x-x-||
#  S|--------o-------||
#  B|o---------------||
#    1 + 2 + 3 + 4 +

for my $beat (0..15) {
    $sequencer->[beat($beat*4+2,0)] = [
    # Maybe we should pre-cook the OSC message even, to take
    # load out of the output loop
    "/trigger/tb303" => 'iiffi',
        #(70+int(rand(12)), 0.125, 60+int(rand(50)), 0.8, 0)
        (40+int(rand(24)), 130, 0.1, 0.8+rand(0.15), 0)
    ];
	# 1/4 bassdrum
	#if( $beat % 4 == 0 ) {
	#	$sequencer->[beat($beat*4,1)] =
	#		$osc->message("/trigger/bd", 'i' => 5);
	#	;
	#}
	## 1/8 hi-hat
    #$sequencer->[beat($beat*4,2)] =
    #    $osc->message("/trigger/hh", 'i' => 1);
    #;
    #$sequencer->[beat($beat*4+2,2)] =
    #    $osc->message("/trigger/hh", 'i' => 1);
    #;
}

# we expect each char to be a 16th note
sub parse_drum_pattern( $sequencer, $track, $pattern, $osc_message ) {
	$pattern =~ m!^\s*\w+\s*\|((?:[\w\-]{16})+)\|+!
	    or croak "Invalid pattern '$pattern'";
	my @beats = split //, $1;
	my $ofs = 0;

	while( $ofs < @beats ) {
		if( $beats[ $ofs ] ne '-' ) {
			$sequencer->[beat($ofs,$track)] =
			    $osc->message($osc_message, 'f' => 0.75);
			;
		}
		$ofs++;
	}
}

# 64 16th notes
# Half Drop
#                                     1   2   3   4   1   2   3   4
#parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-||', '/trigger/hh');
#parse_drum_pattern($sequencer, 3, ' S|--------o---------------o---------------o---------------o-------||', '/trigger/sn');
#parse_drum_pattern($sequencer, 3, ' B|o---------------o---------------o---------------o---------------||', '/trigger/bd');

# One Drop
#                                     1   2   3   4   1   2   3   4
parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-||', '/trigger/hh');
parse_drum_pattern($sequencer, 3, ' S|--------o---------------o---------------o---------------o-------||', '/trigger/sn');
parse_drum_pattern($sequencer, 4, ' B|o-------o-------o-------o-------o-------o-------o-------o-------||', '/trigger/bd');


# Reggaeton
# Is this too slow?!
#parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-||', '/trigger/hh');
#parse_drum_pattern($sequencer, 3, ' S|----------------------o-----o-------------------------o-----o---||', '/trigger/sn');
#parse_drum_pattern($sequencer, 3, ' B|o-------o-------o-------o-------o-------o-------o-------o-------||', '/trigger/bd');


# "Expand" the array to the full length
my $last = beat(16*4,0)-1;
$sequencer->[$last]= undef;

my $tick = 0;
my $ticks_in_bar = @$sequencer / $tracks;

die "data structure is not a complete bar ($ticks_in_bar)" if int($ticks_in_bar) != $ticks_in_bar;
say "You have defined $ticks_in_bar ticks";

$| = 1;

# Periodically swap $sequencer for the next bar/ set of 16 beats / whatever

# We should be able to pause / restart / resume / resync the code
# For resync, we need to keep track of the start time or increase our tick counter
# Currently we simply increase our tick counter while we are silent. This means
# we have no real "pause". We need to store two tick states.

my $output_state = '';

sub play_sounds {
	my $loc = loc($tick, 0) % @$sequencer;

	if( $output_state eq 'silent' ) {
		# do nothing
	} else {
		print sprintf "%d / %d / %d\r", $tick, $loc, scalar @$sequencer;
		for my $s ($loc..$loc+$tracks-1) {
			my $n = $sequencer->[$s];
			if( $n ) {
				my $r = ref $n;
				if( $r ) {
					if( $r eq 'CODE' ) {
						# Can we pass any meaningful parameters here?
						# Like maybe the current tick?!
						send_osc( $udp, $n->($tick) );
					} elsif( $r eq 'ARRAY' ) {
						send_osc( $udp, @$n );
					}

				} else {
		print sprintf "%d / %d / %d - $ticks_in_bar - beat\r\n", $tick, $loc, scalar @$sequencer;
					send_osc_msg( $udp, $n );
				}
			}
		}
	}
	# Consider calculating the tick from the start of the
	# playtime instead of blindly increasing it?!
	$tick = ($tick+1)%$ticks_in_bar;

}


my $timer = IO::Async::Timer::Periodic->new(
    reschedule => 'skip',
    first_interval => 0,
    interval => 60/$bpm/$beats/$ticks,
    on_tick => \&play_sounds,
);

# send_osc "/loader/require", "tempfile" ?!
# send_osc "/eval", "ruby code"?!

$timer->start;
$loop->add( $timer );
$loop->run;