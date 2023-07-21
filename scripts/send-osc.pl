#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp 'croak';

use IO::Async::Loop;
use IO::Async::Timer::Periodic;
use Net::Async::OSC;

my $loop = IO::Async::Loop->new();
my $osc = Net::Async::OSC->new(
    loop => $loop,
);
$osc->connect('127.0.0.1', 4560)->get;

my $bpm    = 120;
my $beats  = 4; # 4/4
my $ticks  = 4; # ticks per beat, means 1/16th notes
my $tracks = 8; # so far...

sub loc($tick, $track) {
    $tick*$tracks+$track
}

sub beat($beat, $track) {
    return loc($ticks*$beat,$track)
}

my $sequencer = [];

for my $beat (0..7) {
    $sequencer->[beat($beat*8+4,0)] = [
    # Maybe we should pre-cook the OSC message even, to take
    # load out of the output loop
    "/trigger/tb303" => 'iiffi',
        #(70+int(rand(12)), 0.125, 60+int(rand(50)), 0.8, 0)
        (40+int(rand(24)), 130, 0.1, 0.8+rand(0.15), 0)
    ];
}

# The harmonies
my $base = 64;
my @harmonies = ([$base,'major'],
				 [$base,'major'],
				 [$base+5,'m7'],
				 [$base+5,'m7'],
				 [$base,'major'],
				 [$base,'major'],
				 [$base+7,'dim'],
				 [$base+7,'dim'],
	);
	
my $harmony = -1;

my @bassline = (split //, "o-------o---------------o---o---");
my $bass_ofs = 0;
for my $beat (0..7) {
	$harmony = ($harmony+1)%@harmonies;
    $sequencer->[beat($beat*8+4,1)] = [
    # Maybe we should pre-cook the OSC message even, to take
    # load out of the output loop
    "/trigger/chord" => 'is', ($harmonies[ $harmony ]->@* )
    ];
	
	# Bassline
	for my $ofs (0..7) {
		if( $bassline[ $bass_ofs ] ne '-' ) {
			$sequencer->[beat($beat*8+$ofs,5)] = [
				"/trigger/bass" => 'i', ($harmonies[ $harmony ]->[0] - 24 )
			];
		};
		$bass_ofs = (($bass_ofs+1) % scalar @bassline)
	}
}

# Another track with a "bassline" based on the harmonies above
# Should we model the bass like a drum?!

# Another track with a "melody" based on the harmonies above

# we expect each char to be a 32th note (?!)
sub parse_drum_pattern( $sequencer, $track, $pattern, $osc_message,$vol=1,$ticks_per_note=undef) {
	$pattern =~ m!^\s*\w+\s*\|((?:[\w\-]{16})+)\|+!
	    or croak "Invalid pattern '$pattern'";
	$ticks_per_note //= length($1) / 4;
	my $p = $1;
	while( length $p < 256 / $ticks_per_note) {
		$p .= $1;
	}
		say $p;
	my @beats = split //, $p;
	my $ofs = 0;

	while( $ofs < @beats ) {
		if( $beats[ $ofs ] ne '-' ) {
			$sequencer->[loc($ofs*$ticks_per_note,$track)] =
			    $osc->osc->message($osc_message, 'f' => $vol);
		} else {
			$sequencer->[loc($ofs*$ticks_per_note,$track)] =
			    undef;
		}
		$ofs++;
	}
	print "\r". loc(($ofs-1)*$ticks_per_note,$track);
	print "\n";
}

# 64 16th notes
# Half Drop
#                                      1       2       3       4       1       2       3       4   
#parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-||', '/trigger/hh');
#parse_drum_pattern($sequencer, 3, ' S|--------o---------------o---------------o---------------o-------||', '/trigger/sn');
#parse_drum_pattern($sequencer, 3, ' B|o---------------o---------------o---------------o---------------||', '/trigger/bd');

# One Drop
parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-||', '/trigger/hh',1,4);
parse_drum_pattern($sequencer, 3, ' S|--------o-------||', '/trigger/sn',1,4);
parse_drum_pattern($sequencer, 4, ' B|--------o-------||', '/trigger/bd',1,4);


# Reggaeton
#parse_drum_pattern($sequencer, 2, 'HH|x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-x-||', '/trigger/hh',0.25,2);
#parse_drum_pattern($sequencer, 3, ' B|o-------o-------o-------o-------||', '/trigger/bd',1,2);
#parse_drum_pattern($sequencer, 3, ' S|----------------------o-----o---||', '/trigger/sn',1,2);

# "Expand" the array to the full length
# This should simply be the next multiple of $beats*$ticks*$tracks, no?!
my $last = beat(16,0) -1;
$sequencer->[$last]= undef;

# Round up to a 4/4 bar
say $last;
say scalar @$sequencer;
my $ticks_in_bar = @$sequencer / $tracks;
while( int( $ticks_in_bar ) != $ticks_in_bar ) {
	$ticks_in_bar = int($ticks_in_bar)+1;
	
	while( $ticks_in_bar % 16 != 0 ) {
		$ticks_in_bar += (16 - ($ticks_in_bar % 16));
	}
	
	# expand
	$sequencer->[loc($ticks_in_bar,0)-1] = undef;
	
	say (@$sequencer / $tracks);
}

my $tick = 0;
my $ticks_in_bar = @$sequencer / $tracks;

die "data structure is not a complete bar ($ticks_in_bar)" if int($ticks_in_bar) != $ticks_in_bar;
say "You have defined $ticks_in_bar ticks";

$| = 1;

# Periodically swap $sequencer for the next bar/ set of 16 beats / whatever
# Also bridge, breakdown, drop

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
		#print sprintf "%d / %d / %d\r", $tick, $loc, scalar @$sequencer;
		for my $s ($loc..$loc+$tracks-1) {
			my $n = $sequencer->[$s];
			if( $n ) {
				my $r = ref $n;
				if( $r ) {
					if( $r eq 'CODE' ) {
						# Can we pass any meaningful parameters here?
						# Like maybe the current tick?!
						$osc->send_osc( $n->($tick) );
					} elsif( $r eq 'ARRAY' ) {
						$osc->send_osc( @$n );
					}

				} else {
		#print sprintf "%d / %d / %d - $ticks_in_bar - beat\r", $tick, $loc, scalar @$sequencer;
					$osc->send_osc_msg( $n );
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

__END__

[ ] Have multiple progressions, and switch between those
[ ] Move code from main program into subroutines, "expand_progression()"
[ ] Patterns can then become expand_pattern("AABA"), which calls expand_progression()
[ ] Songs are patterns like "IIAABBAABBCCBBCxAABBAABBAABBCCBBCCBBCCBBCCBBOO"
    where "II" are intro patterns (without melody)
	      "OO" are outro patterns
	      "xx" are breakdown patterns
