#!/usr/bin/perl

# Streaming through the HTTP filter, including upstream chunk boundaries.

use warnings;
use strict;
use Test::More;
use IO::Select;
use Socket qw/ SOL_SOCKET SO_RCVBUF TCP_NODELAY IPPROTO_TCP /;
use Digest::SHA qw/ sha256_hex /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content http_end /;

my @cases = (
    ['tag and comment', '<p  >hello   world</p><!--remove-->',
        '<p>hello   world</p>'],
    ['raw text', '<title>a <!--keep--> b</title>',
        '<title>a <!--keep--> b</title>'],
    ['script comment', '<script>var/**/x = 1;</script>',
        '<script>var/**/x = 1;</script>'],
    ['CSS custom property', '<style>.x { --pair: a/**/b; }</style>',
        '<style>.x { --pair: a/**/b; }</style>'],
    ['unfinished opener', '<p>x</p><', '<p>x</p><'],
    ['unfinished comment opener', '<p>x</p><!-', '<p>x</p><!-'],
    ['unfinished comment', '<p>x</p><!--unfinished', '<p>x</p><!--unfinished'],
    ['unfinished attribute', "<p title='unfinished>", "<p title='unfinished>"],
    ['unfinished raw end tag', '<script>x</scrip', '<script>x</scrip'],
    ['empty output', '<!--remove-->', ''],
    ['short comment terminators', '<!-->a<!--->b<!--x--!>c', 'abc'],
    ['binary text', "<p>a\0\xff  b</p>", "<p>a\0\xff  b</p>"],
);
my $long = '<p  title="' . ('x' x 5000) . '">a  b<!--keep--></p>';
push @cases, ['oversized tag', $long, $long];

my @requests;
for my $i (0 .. $#cases) {
    my $len = length($cases[$i][1]);
    my @cuts = $len < 100 ? (0 .. $len) : (0, 1, 4095, 4096, 4097, $len);
    push @requests, map { [$i, $_] } @cuts;
    push @requests, [$i, 'byte'] if $len < 100;
}

my $piece = '<p  id = "x">hello   world</p><!--drop-->';
my $trimmed = '<p id="x">hello   world</p>';
my $repetitions = 160000;
my $t = Test::Nginx->new()->has(qw/http proxy trim_filter/)
    ->plan(2 * @requests + 5);

$t->write_file_expand('nginx.conf', <<'EOF');
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080 sndbuf=32k;
        trim on;
        trim_js on;
        trim_css on;
        location / {
            proxy_buffering off;
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

$t->run_daemon(\&http_daemon, $t->testdir());
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

for my $request (@requests) {
    my ($i, $cut) = @$request;
    my $name = "$cases[$i][0], chunk $cut";
    my $response = http_get("/$i/$cut");
    like($response, qr/^HTTP\/1\.[01] 200 /, "$name status");
    is(http_content($response), $cases[$i][2], "$name body");
}

# Hold the rest of the upstream response until the client sees the first body.
# This verifies early output without relying on a short timing threshold.
my $s = http_get('/early', start => 1);
my $select = IO::Select->new($s);
my $first = '';
while ($select->can_read(3)) {
    my $n = sysread($s, my $data, 4096);
    last unless $n;
    $first .= $data;
    last if $first =~ /\r\n\r\n<p>first<\/p>$/;
}
like($first, qr/\r\n\r\n<p>first<\/p>$/, 'body sent before upstream finishes');
$t->write_file('continue', '');
is(http_content($first . http_end($s)), '<p>first</p><p>second</p>',
    'early response completes');

# Fill the small socket buffers before draining the response slowly.
$s = IO::Socket::INET->new(
    Proto => 'tcp',
    PeerAddr => '127.0.0.1:' . port(8080),
) or die "Can't connect to nginx: $!\n";
setsockopt($s, SOL_SOCKET, SO_RCVBUF, pack('i', 65536))
    or die "Can't set receive buffer: $!\n";
$s = http_get('/large', socket => $s, start => 1);
select undef, undef, undef, 0.2;

my $response = '';
{
    local $SIG{ALRM} = sub { die "slow client timed out\n" };
    alarm(60);
    while (1) {
        my $n = sysread($s, my $data, 4096);
        die "Can't read response: $!\n" unless defined $n;
        last unless $n;
        $response .= $data;
        select undef, undef, undef, 0.001;
    }
    alarm(0);
}
close $s;
like($response, qr/^HTTP\/1\.[01] 200 /, 'slow client status');
my $body = http_content($response);
my $expected = $trimmed x $repetitions;
is(length($body), length($expected), 'slow client output length');
is(sha256_hex($body), sha256_hex($expected), 'slow client output content');

sub chunk {
    my ($client, $data) = @_;
    return unless length($data);
    printf $client "%x\r\n%s\r\n", length($data), $data;
}

sub http_daemon {
    my ($dir) = @_;
    my $server = IO::Socket::INET->new(
        Proto => 'tcp',
        LocalAddr => '127.0.0.1:' . port(8081),
        Listen => 5,
        Reuse => 1,
    ) or die "Can't create listening socket: $!\n";

    local $SIG{PIPE} = 'IGNORE';
    while (my $client = $server->accept()) {
        $client->autoflush(1);
        setsockopt($client, IPPROTO_TCP, TCP_NODELAY, pack('i', 1));
        my $line = <$client>;
        next unless defined $line;
        my ($uri) = $line =~ /^\S+ (\S+) /;
        while (<$client>) {
            last if /^\r?\n$/;
        }
        print $client "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
            . "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n";

        if ($uri eq '/large') {
            my $data = $piece x $repetitions;
            for (my $i = 0; $i < length($data); $i += 4096) {
                chunk($client, substr($data, $i, 4096));
            }
        } elsif ($uri eq '/early') {
            chunk($client, '<p>first</p>');
            for (1 .. 500) {
                last if -e "$dir/continue";
                select undef, undef, undef, 0.01;
            }
            chunk($client, '<p>second</p>');
        } elsif ($uri =~ m{^/(\d+)/(\d+|byte)$}) {
            my ($i, $cut) = ($1, $2);
            my $data = $cases[$i][1];
            if ($cut eq 'byte') {
                for my $c (split //, $data) {
                    chunk($client, $c);
                    select undef, undef, undef, 0.003;
                }
            } else {
                chunk($client, substr($data, 0, $cut));
                select undef, undef, undef, 0.003;
                chunk($client, substr($data, $cut));
            }
        }
        print $client "0\r\n\r\n";
        close $client;
    }
}
