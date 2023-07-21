package Net::Async::OSC;
use 5.020;
use Moo 2;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp 'croak';

our $VERSION = '0.01';

use Protocol::OSC;
use IO::Async::Loop;
use IO::Async::Socket;
use Socket 'pack_sockaddr_in', 'inet_aton'; # IPv6 support?!

has 'osc' => (
   is => 'lazy',
   default => sub { return Protocol::OSC->new },
);

has 'loop' => (
   is => 'lazy',
   default => sub { return IO::Async::Loop->new },
);

has 'socket' => (
    is => 'rw',
);

sub connect( $self, $host, $port ) {
    my $loop = $self->loop;
    my $pingback = IO::Async::Socket->new(
        on_recv => sub( $sock, $data, $addr, @rest ) {
            warn "Reply: $data";
        },
    );
    $loop->add( $pingback );
    # What about multihomed hosts?!
    return $pingback->connect(
        host => $host,
        service => $port,
        socktype => 'dgram'
    )->on_done(sub($socket) {
		$self->socket($socket)
	});
}

sub send_osc( $self, @message ) {
	my $osc = $self->osc;
	my $socket = $self->socket;
    my $data = $osc->message(@message); # pack
    $self->send_osc_msg( $data );
}

sub send_osc_msg( $self, $data ) {
    #say join " , " , @{ $osc->parse( $data ) };
    $self->socket->send( $data );
}

1;