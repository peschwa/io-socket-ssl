class IO::Socket::SSL;

use NativeCall;
use OpenSSL;
use OpenSSL::SSL;
use OpenSSL::Err;

use libclient;

sub client_connect(Str, int32) returns int32 { * }
sub client_disconnect(int32) { * }
sub server_init(int32, int32, Str) returns int32 { * }
trait_mod:<is>(&client_connect, :native(libclient::library));
trait_mod:<is>(&client_disconnect, :native(libclient::library));
trait_mod:<is>(&server_init, :native(libclient::library));

sub v4-split($uri) {
    $uri.split(':', 2);
}
sub v6-split($uri) {
    my ($host, $port) = ($uri ~~ /^'[' (.+) ']' \: (\d+)$/)[0, 1];
    $host ?? ($host, $port) !! $uri;
}

has Str $.encoding = 'utf8';
has Str $.host;
has Int $.port = 80;
has Str $.localhost;
has Int $.localport;
has Str $.certfile;
has Bool $.listen;
#has $.family = PIO::PF_INET;
#has $.proto = PIO::PROTO_TCP;
#has $.type = PIO::SOCK_STREAM;
has Str $.input-line-separator is rw = "\n";
has Int $.ins = 0;

has int32 $.fd;
has OpenSSL $.ssl;

method new(*%args is copy) {
    fail "Nothing given for new socket to connect or bind to" unless %args<host> || %args<listen>;

    if %args<host> {
        my ($host, $port) = %args<family> && %args<family> == PIO::PF_INET6()
            ?? v6-split(%args<host>)
            !! v4-split(%args<host>);
        if $port {
            %args<port> //= $port;
            %args<host> = $host;
        }
    }
    if %args<localhost> {
        my ($peer, $port) = %args<family> && %args<family> == PIO::PF_INET6()
            ?? v6-split(%args<localhost>)
            !! v4-split(%args<localhost>);
        if $port {
            %args<localport> //= $port;
            %args<localhost> = $peer;
        }
    }

    %args<listen>.=Bool if %args.exists_key('listen');

    self.bless(|%args)!initialize;
}

method !initialize {
    if $!host && $!port {
        # client stuff
        my int32 $port = $!port;
        $!fd = client_connect($!host, $port);

        if $!fd > 0 {
            # handle errors
            $!ssl = OpenSSL.new(:client);
            $!ssl.set-fd($!fd);
            $!ssl.set-connect-state;
            my $ret = $!ssl.connect;
            if $ret < 0 {
                my $e = OpenSSL::Err::ERR_get_error();
                repeat {
                    say "err code: $e";
                    say OpenSSL::Err::ERR_error_string($e);
                   $e = OpenSSL::Err::ERR_get_error();
                } while $e != 0 && $e != 4294967296;
            }
        }
        else {
            die "Failed to connect";
        }
    }
    elsif $!localhost && $!localport {
        my int32 $listen = $!listen.Int // 0;
        $!fd = server_init($!localport, $listen, $!certfile);
        if $!fd > 0 {
            $!ssl = OpenSSL.new;
            $!ssl.set-fd($!fd);
            $!ssl.set-accept-state;

            die "No certificate file given" unless $!certfile;
            $!ssl.use-certificate-file($!certfile);
            $!ssl.use-privatekey-file($!certfile);
            $!ssl.check-private-key;
        }
        else {
            die "Failed to " ~ ($!fd == -1 ?? "bind" !! "listen");
        }
    }
    self;
}

method recv(Int $n = 1048576, Bool :$bin = False) {
    $!ssl.read($n, :$bin);
}

method send(Str $s) {
    $!ssl.write($s);
}

method accept {
    $!ssl.accept;
}

method close {
    $!ssl.close;
    client_disconnect($!fd);
}

=begin pod

=head1 NAME

IO::Socket::SSL - interface for SSL connection

=head1 SYNOPSIS

    use IO::Socket::SSL;
    my $ssl = IO::Socket::SSL.new(:host<example.com>, :port(443));
    if $ssl.send("GET / HTTP/1.1\r\n\r\n") {
        say $ssl.recv;
    }

=head1 DESCRIPTION

This module provides an interface for SSL connections.

It uses C to setting up the connection so far (hope it will change soon).

=head1 METHODS

=head2 method new

    method new(*%params) returns IO::Socket::SSL

Gets params like:

=item encoding             : connection's encoding
=item input-line-separator : specifies how lines of input are separated

for client state:
=item host : host to connect
=item port : port to connect

for server state:
=item localhost : host to use for the server
=item localport : port for the server
=item listen    : create a server and listen for a new incoming connection
=item certfile  : path to a file with certificates

=head2 method recv

    method recv(IO::Socket::SSL:, Int $n = 1048576, Bool :$bin = False)

Reads $n bytes from the other side (server/client).

Bool :$bin if we want it to return Buf instead of Str.

=head2 method send

    method send(IO::Socket::SSL:, Str $s)

Sends $s to the other side (server/client).

=head2 method accept

    method accept(IO::Socket::SSL:)

Waits for a new incoming connection and accepts it.

=head2 close

    method close(IO::Socket::SSL:)

Closes the connection.

=head1 SEE ALSO

L<OpenSSL>

=head1 EXAMPLE

To download sourcecode of e.g. github.com:

    use IO::Socket::SSL;
    my $ssl = IO::Socket::SSL.new(:host<github.com>, :port(443));
    my $content = Buf.new;
    $ssl.send("GET /\r\n\r\n");
    while my $read = $ssl.recv {
        $content ~= $read;
    }
    say $content;

=end pod
