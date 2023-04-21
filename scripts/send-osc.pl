#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';

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
	say join " , " , @{ $osc->parse( $data ) };
	$socket->send( $data );
}

my $loop = IO::Async::Loop->new();
my $udp = new_socket($loop, '127.0.0.1', 4560);

my $bpm = 120;

my $sequencer = [
];

my $timer = IO::Async::Timer::Periodic->new(
	reschedule => 'skip',
	first_interval => 0,
	interval => 60/$bpm,
	on_tick => sub {
		my ($note, $release, $cutoff, $res, $wave) = (70+int(rand(12)), 0.125, 60+int(rand(50)), 0.8, 0);
		send_osc( $udp, "/trigger/tb303" => 'ififi', $note, $release, $cutoff, $res, $wave );
	},
);

# send_osc "/loader/require", "tempfile" ?!
# send_osc "/eval", "ruby code"?!

$timer->start;
$loop->add( $timer );
$loop->run;
