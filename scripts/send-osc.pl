#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp 'croak';

use lib '../Term-Output-List/lib';
use Term::Output::List;

use IO::Async::Loop;
use IO::Async::Timer::Periodic;
use Net::Async::OSC;
use Music::VoiceGen;
use Music::Scales;
use Music::Chord::Note;
my $loop = IO::Async::Loop->new();
my $osc = Net::Async::OSC->new(
    loop => $loop,
);
$osc->connect('127.0.0.1', 4560)->get;

my @track_names = (qw(
    <harmony>
    chord
    hh
    snare
    bassdrum
    bass
    melody
    777
));

my $t = Term::Output::List->new();
my $input;
if( $^O eq 'MSWin32') {
    $input = Win32::Console->new(Win32::Console::STD_INPUT_HANDLE());
}
sub msg($msg) {
    $t->output_permanent($msg);
}

my $bpm    = 97;
my $beats  = 4; # 4/4
my $ticks  = 4; # ticks per beat, means 1/16th notes
my $tracks = 8; # so far...

sub loc($tick, $track) {
    $tick*$tracks+$track
}

sub beat($beat, $track) {
    return loc($ticks*$beat,$track)
}

# create_sequencer() ?
my $sequencer = [];

sub random_melody( $track ) {
    for my $beat (0..7) {
        $sequencer->[beat($beat*8+4,$track)] = [
        # Maybe we should pre-cook the OSC message even, to take
        # load out of the output loop
        "/trigger/tb303" => 'iiffi',
            #(70+int(rand(12)), 0.125, 60+int(rand(50)), 0.8, 0)
            (40+int(rand(24)), 130, 0.1, 0.8+rand(0.15), 0)
        ];
    }
}

# The harmonies
# Maybe we want markov-style progressions, or some other weirdo set?
my $base = 50 + int(rand(32));
my @harmonies = ([$base,  'major'], #C
                 [$base,  'major'],
                 #[$base,  'M7'],
                 [$base+7,'major'], #G
                 [$base+7,'major'], #G
                 [$base+9,'min'],   #A
                 [$base+9,'min'],
                 [$base+5,'major'], #F
                 [$base+5,'major'], #F
                 #[$base+5,'M7'],
                 [$base,  'major'], #C
                 [$base,  'major'], #C
                 [$base+7,'major'], #G
                 [$base+7,'major'], #G
                 [$base,  'major'], #C
                 [$base,  'major'], #C
                 [$base+7,'major'], #G
                 [$base+7,'major'], #G
);

my $bass_harmony = -1;
my $chord_track = 1;
my $info_track = 0;

my @bassline = (split //, "o-------o---------------o---o---");
my $bass_ofs = 0;
for my $beat (0..$#harmonies) {
    $bass_harmony = ($bass_harmony+1)%@harmonies;
    my $ofs = beat($beat*8+4,$info_track);
    $sequencer->[$ofs+$_*$tracks] = sprintf "%d %s", $harmonies[ $bass_harmony ]->@*
        for 0..$ticks*$beats-1;
    $sequencer->[beat($beat*8+4,$chord_track)] = [
        # Maybe we should pre-cook the OSC message even, to take
        # load out of the output loop
        "/trigger/chord" => 'is', ($harmonies[ $bass_harmony ]->@* )
    ];

    # Bassline
    for my $ofs (0..7) {
        if( $bassline[ $bass_ofs ] ne '-' ) {
            $sequencer->[beat($beat*8+$ofs,5)] = [
                "/trigger/bass" => 'i', ($harmonies[ $bass_harmony ]->[0] - 24 )
            ];
        };
        $bass_ofs = (($bass_ofs+1) % scalar @bassline)
    }
}

# Another track with a "bassline" based on the harmonies above
# Should we model the bass like a drum?!
my %chord_names = (
    'M7'  => 'M7',
    min   => 'm',
    major => 'base',
);

sub melody_step( $tick, $base, $curr_harmony, $next_harmony, $last_note ) {
    my $h = $harmonies[ $curr_harmony ];
    my $chord_name = $chord_names{ $h->[1]} // $h->[1];
    my $cn = Music::Chord::Note->new();

    # Cache this?!
    #my @scale = map { $_ + $h->[0], $_ + $h->[0]+12 } $cn->chord_num( $chord_name );
    # these are only the boring notes, but I'm not sure how to bring half-tones
    # and harmonic progression stuff in here

    # For the harmonic stuff, we know what scales match to our chords:
    my %scales = (
        major => 'major',
        min   => 'minor',
        'M7'  => 'major',
    );
    my $scale_name = $scales{ $h->[1] }
        or die "Unknown harmony '$h->[1]'";
    my $chord_name = $chord_names{ $h->[1] }
        or die "Unknown harmony '$h->[1]' for chord";
    my @scale;

    if( $sequencer->[beat($tick*8+4,$chord_track)]) {
        # Use a note in line with the currently playing chord
        my $cn = Music::Chord::Note->new();
        @scale = map { $base + $_ } $cn->chord_num($chord_name);
    } else {
        # Use a random note
        @scale = get_scale_MIDI($base, 4, $scale_name, 0);
    }
    return $scale[ int rand @scale ];
}

# Another track with a "melody" based on the harmonies above
sub generate_melody( $harmonies, $sequencer, $track ) {
    #my @melody = (split //, "--o-o---o-o-o---o-o-o---o-o-o---");
    my @melody = (split //, "o-------");

    my $harmony = -1;

    my $rhythm_ofs = 0;
    for my $beat (0..$#$harmonies) {
        # Select the next harmony
        $harmony = ($harmony+1)%@$harmonies;
        my $next_harmony = ($harmony+1)%@$harmonies;
        my $last_note;
        for my $ofs (0..7) {
            if( $melody[ $rhythm_ofs ] ne '-' ) {
                my $note = melody_step( $ofs, $base, $harmony, $next_harmony, $last_note );
                $sequencer->[beat($beat*8+$ofs,$track)] = [
                    "/trigger/melody" => 'i', ($note)
                ];
                $last_note = $note;
            };
            $rhythm_ofs = (($rhythm_ofs+1) % scalar @melody)
        }
    }
}

# we expect each char to be a 32th note (?!)
# We need to repeat the pattern until it fills the longest other pattern!
sub parse_drum_pattern( $sequencer, $total_bars, $track, $pattern, $osc_message,$vol=1,$ticks_per_note=undef) {
    $pattern =~ m!^\s*\w+\s*\|((?:[\w\-]{16})+)\|+!
        or croak "Invalid pattern '$pattern'";
    $ticks_per_note //= length($1) / 4;
    my $p = $1;
    my $target_len = $total_bars*$beats*$ticks*2 / $ticks_per_note; # the 2 is because each total_bar is 2 bars
    while( length $p < $target_len) {
        $p .= $1;
    }
    msg( $p );
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
}

# Half Drop
sub generate_half_drop( $sequencer, $total_bars ) {
    parse_drum_pattern($sequencer, $total_bars, 2, 'HH|x-x-x-x-x-x-x-x-||', '/trigger/hh');
    parse_drum_pattern($sequencer, $total_bars, 3, ' S|--------o-------||', '/trigger/sn');
    parse_drum_pattern($sequencer, $total_bars, 4, ' B|o-------o-------||', '/trigger/bd');
}

# One Drop
sub generate_one_drop( $sequencer, $total_bars ) {
    parse_drum_pattern($sequencer, $total_bars, 2, 'HH|x-x-x-x-x-x-x-x-||', '/trigger/hh',1,4);
    parse_drum_pattern($sequencer, $total_bars, 3, ' S|--------o-------||', '/trigger/sn',1,4);
    parse_drum_pattern($sequencer, $total_bars, 4, ' B|--------o-------||', '/trigger/bd',1,4);
}

# Reggaeton
sub generate_reggaeton( $sequencer, $total_bars ) {
    parse_drum_pattern($sequencer, $total_bars, 2, 'HH|x---x---x---x---x---x---x---x---||', '/trigger/hh',0.25,2);
    parse_drum_pattern($sequencer, $total_bars, 3, ' B|o-------o-------o-------o-------||', '/trigger/bd',1,2);
    parse_drum_pattern($sequencer, $total_bars, 4, ' S|----------------------o-----o---||', '/trigger/sn',1,2);
}
generate_one_drop($sequencer, scalar @harmonies);
generate_melody( \@harmonies, $sequencer, 6 );

# "Expand" the array to the full length
# This should simply be the next multiple of $beats*$ticks*$tracks, no?!
my $last = beat(16,0) -1;
$sequencer->[$last]= undef;

# Round up to a 4/4 bar
msg( $last );
msg( scalar @$sequencer );
my $ticks_in_bar = @$sequencer / $tracks;
while( int( $ticks_in_bar ) != $ticks_in_bar ) {
    $ticks_in_bar = int($ticks_in_bar)+1;

    while( $ticks_in_bar % 16 != 0 ) {
        $ticks_in_bar += (16 - ($ticks_in_bar % 16));
    }

    # expand
    $sequencer->[loc($ticks_in_bar,0)-1] = undef;

    msg(@$sequencer / $tracks);
}

my $tick = 0;
my $ticks_in_bar = @$sequencer / $tracks;

die "data structure is not a complete bar ($ticks_in_bar)" if int($ticks_in_bar) != $ticks_in_bar;
msg( "You have defined $ticks_in_bar ticks" );

$| = 1;

# Periodically swap $sequencer for the next bar/ set of 16 beats / whatever
# Also bridge, breakdown, drop

# We should be able to pause / restart / resume / resync the code
# For resync, we need to keep track of the start time or increase our tick counter
# Currently we simply increase our tick counter while we are silent. This means
# we have no real "pause". We need to store two tick states.

my $output_state = '';

my @playing = ('' x (1+$tracks));
my @mute    = ('' x (1+$tracks));

sub toggle_mute($track, $mute=undef) {
    my $val = $mute;

    if( ! defined $val ) {
        if( $mute[ $track ] ) {
            $val = '';
        } else {
            $val = 'mute';
        }
    }

    $mute[ $track ] = $val;
}

sub play_sounds {
    my $loc = loc($tick, 0) % @$sequencer;

    # Win32 specific...
    while( $input and $input->GetEvents ) {
        #msg( sprintf "Pending: %d", $input->GetEvents );
        my @ev = $input->Input();
        if( $ev[0] == 1 and $ev[1] ) {
            my $key = chr($ev[5]);
            if( $key =~ /\d/ ) {
                toggle_mute($key);
            } elsif( $key eq 'm' ) {
                toggle_mute($_, 'mute') for 0..$tracks-1;
            } elsif( $key eq 'u' ) {
                toggle_mute($_, '') for 0..$tracks-1;
            } elsif( $key eq 'q' ) {
                $loop->stop;
            } else {
                msg("Keypress '$key' ($ev[5])")
                    if $key =~ /\S/;
            }
        }
    }

    if( $output_state eq 'silent' ) {
        # do nothing
    } else {
        for my $s ($loc..$loc+$tracks-1) {
            my $track = $s-$loc;
            my $n = $sequencer->[$s];
            if( $n ) {
                $playing[ $track ] = $n;
                if( ! $mute[ $track ]) {
                    my $r = ref $n;
                    if( $r and not $mute[$track] ) {
                        if( $r eq 'CODE' ) {
                            # Can we pass any meaningful parameters here?
                            # Like maybe the current tick?!
                            $osc->send_osc( $n->($tick) );
                        } elsif( $r eq 'ARRAY' ) {
                            $osc->send_osc( @$n );
                        }

                    } elsif( $track == 0 ) {
                        $playing[0] = $n;

                    } else {
                        $osc->send_osc_msg( $n );
                    }
                }
            } else {
                $playing[ $track ] = '';
            }
        }

        my @output = map {
            sprintf "%d| %8s | % 12s | %s", $_, $mute[$_], $track_names[$_], $playing[$_];
        } 0..$tracks-1;
        $t->output_list(@output);
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
[ ] Have bass/melody pause at some times
[ ] Insert a breakdown/bridge pattern