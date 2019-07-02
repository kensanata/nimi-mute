#!/usr/bin/env perl
# Copyright (C) 2019  Alex Schroeder <alex@gnu.org>

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

package Nimi::Ilo;
use Modern::Perl '2018';
use base qw(Net::Server::Fork); # any personality will do
use IO::Socket::IP;
use MIME::Base64;
use Mojo::URL;
use Encode;

# Sadly, we need this information before doing anything else
my $scheme;
my %args = (proto => 'ssl');
for (grep(/--(key|cert)_file=/, @ARGV)) {
  $args{SSL_cert_file} = $1 if /--cert_file=(.*)/;
  $args{SSL_key_file} = $1 if /--key_file=(.*)/;
}
if ($args{SSL_cert_file} and not $args{SSL_key_file}
    or not $args{SSL_cert_file} and $args{SSL_key_file}) {
  die "I must have both --key_file and --cert_file\n";
} elsif ($args{SSL_cert_file} and $args{SSL_key_file}) {
  $scheme = "https";
  Nimi::Ilo->run(%args);
} else {
  $scheme = "http";
  Nimi::Ilo->run;
}

sub options {
  my $self     = shift;
  my $prop     = $self->{'server'};
  my $template = shift;

  # setup options in the parent classes
  $self->SUPER::options($template);

  $prop->{password} ||= undef;
  $template->{password} = \$prop->{password};
}

my $password;

sub post_configure_hook {
  my $self = shift;
  $self->write_help if @ARGV and $ARGV[0] eq '--help';

  $password = $self->{server}->{password} || $ENV{NIMI_ILO_PASSWORD} || "";

  $self->log(3, "PID $$");
  $self->log(3, "Host " . ("@{$self->{server}->{host}}" || "*"));
  $self->log(3, "Port @{$self->{server}->{port}}");

  # Note: if you use sudo to run nimi-ilo.pl, these options might not work!
  $self->log(4, "--password says $self->{server}->{password}\n") if $self->{server}->{password};
  $self->log(4, "\$NIMI_ILO_PASSWORD says $ENV{NIMI_ILO_PASSWORD}\n") if $ENV{NIMI_ILO_PASSWORD};
  $self->log(3, "Password is $password\n");
}

my $usage = << 'EOT';
This is a gopher to HTTP proxy.

It implements Net::Server and thus all the options available to
Net::Server are also available here. Additional options are available:

--password  - this is the password if you want to enable uploads
--cert_file - the filename containing a certificate in PEM format
--key_file  - the filename containing a private key in PEM format
--port      - the port to listen to, defaults to a random port
--log_level - the log level to use, defaults to 2

Some of these you can also set via environment variables:

NIMI_ILO_PASSWORD

For many of the options, more information can be had in the Net::Server
documentation. This is important if you want to daemonize the server. You'll
need to use --pid_file so that you can stop it using a script, --setsid to
daemonize it, --log_file to write keep logs, and you'll need to set the user or
group using --user or --group such that the server has write access to the data
directory.

Example invocation:

perl nimi-ilo.pl \
    --port=7080 \
    --pid_file=/tmp/nimi-ilo.pid \
    --password=secret

Run the script and test it using curl:

http_proxy=http://localhost:7080/ curl http://alexschroeder.ch

If you want to use SSL, you need to provide PEM files containing certificate and
private key. To create self-signed files, for example:

openssl req -new -x509 -days 365 -nodes -out \
        server-cert.pem -keyout server-key.pem

Make sure the common name you provide matches your domain name!
EOT

run();

sub error {
  my $self = shift;
  my $error = shift;
  my $explanation = shift;
  print "HTTP/1.0 $error\r\n";
  print "Content-Type: text/plain\r\n";
  print "\r\n";
  print "$explanation\r\n";
  $self->log(1, "$error: $explanation\n");
  die "$error: $explanation\n";
}

sub serve_text {
  my $self = shift;
  my $text = shift;
  print "HTTP/1.0 200 OK\r\n";
  print "Content-Type: text/plain; charset UTF-8\r\n";
  print "\r\n";
  print "$text\r\n";
}

sub serve_html {
  my $self = shift;
  my $html = shift;
  print "HTTP/1.0 200 OK\r\n";
  print "Content-Type: text/html; charset UTF-8\r\n";
  print "\r\n";
  print "$html\r\n";
}

sub get_text {
  my $self = shift;
  my $host = shift;
  my $port = shift;
  my $selector = shift;
  $self->log(3, "Querying $host:$port with '$selector'");
  # create client
  my $socket = IO::Socket::IP->new(
    PeerHost => $host,
    PeerPort => $port,
    Type     => SOCK_STREAM,
    Timeout  => 3, )
      or return $self->error("502 Bad Gateway", "could not cont contact $host:$port");
  $socket->print("$selector\r\n");
  undef $/; # slurp
  my $text = <$socket>;
  $self->log(3, "Received " . length($text) . " bytes");
  # $self->log(4, $text);
  $socket->close(); # be explicit
  return decode('UTF-8', $text);
}

sub password_required {
  print "HTTP/1.0 407 Proxy Authentication Required\r\n";
  print "Content-Type: text/plain\r\n";
  print qq{Proxy-Authenticate: Basic realm="Gopher Proxy", charset="UTF-8"\r\n};
  print "\r\n";
  print "This Gopher proxy is not public.\r\n";
  die "401 Unauthorized: This Gopher proxy is not public.\n";
}

sub password_matches {
  return 1 unless $password;
  my $auth = shift;
  return 0 unless $auth;
  my ($method, $token) = split / /, $auth;
  return 0 unless $method eq "Basic";
  my ($username, $password_provided) = split /:/, decode_base64($token);
  return 0 unless $password_provided;
  return $password_provided eq $password;
}

sub get_menu {
  my $buf = "<pre>";
  $_ = get_text(@_);
  for (split /\r?\n/) {
    if (/^(?<type>[01])(?<name>[^\t\n]+)\t(?<selector>[^\t\n]+)\t(?<host>[^\t\n]+)\t(?<port>\d+)$/) {
      # gopher map: gopher link
      my $text = $+{name};
      my $url = "$scheme://$+{host}:$+{port}/$+{type}$+{selector}";
      $buf .= qq{<a href="$url">$text</a>\n};
    } elsif (/^i([^\t\n]*)\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*$/) {
      # gopher map: information
      $buf .= "$1\n";
    }
  }
  $buf .= "</pre>";
  return $buf;
}

sub process_request {
  my $self = shift;

  eval {
    local $SIG{'ALRM'} = sub {
      $self->log(1, "Timeout!");
      die "Timed Out!\n";
    };
    alarm(10); # timeout
    my $request = <STDIN>; # first line
    my %header;
    while (<STDIN>) {
      s/\r$//;
      chomp;
      last unless $_;
      # $self->log(4, "Header: $_");
      my ($key, $value) = split /:\s*/;
      $header{lc $key} = $value;
    }
    return password_required() if not password_matches($header{"proxy-authorization"});
    my ($method, $path, $version) = split(/\s+/, $request);
    return $self->error("400 BAD REQUEST", "this proxy only handles unencrypted servers") if $method eq "CONNECT";
    return $self->error("400 BAD REQUEST", "http only supports GET") unless $method eq "GET";
    my $url = Mojo::URL->new($path);
    return $self->error("400 BAD REQUEST", "you must use http URLs") unless $url->scheme eq 'http';
    return $self->error("400 BAD REQUEST", "no user info supported") if $url->userinfo;
    $self->log(4, "Proxying $url");
    my $host = $url->host;
    my $port = $url->port || 70;
    my $selector = ""; # default is empty
    my $itemtype = "1";  # default is menu
    if ($url->path ne '' and $url->path ne '/') {
      $itemtype = substr($url->path, 1, 1);
      return $self->error("400 BAD REQUEST", "Gopher item type must be 0 or 1, not " . $itemtype)
	  if $itemtype ne "0" and $itemtype ne "1";
      $selector .= substr($url->path, 2);
      $selector .= "?" . $url->query     if $url->query ne "";
      $selector .= "#" . $url->fragment  if $url->fragment;
    }
    if ($itemtype == "0") {
      $self->serve_text($self->get_text($host, $port, $selector));
    } else {
      $self->serve_html($self->get_menu($host, $port, $selector));
    }
    $self->log(4, "Done");
  }
}
