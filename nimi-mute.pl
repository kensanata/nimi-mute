#!/usr/bin/env perl
# Copyright (C) 2019  Alex Schroeder <alex@gnu.org>

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

package Nimi::Mute;
use Modern::Perl '2018';
use base qw(Net::Server::Fork); # any personality will do
use File::Slurp;
use URI::Escape;

# Sadly, we need this information before doing anything else
my %args = (proto => 'ssl');
for (grep(/--(key|cert)_file=/, @ARGV)) {
  $args{SSL_cert_file} = $1 if /--cert_file=(.*)/;
  $args{SSL_key_file} = $1 if /--key_file=(.*)/;
}
if ($args{SSL_cert_file} and not $args{SSL_key_file}
    or not $args{SSL_cert_file} and $args{SSL_key_file}) {
  die "I must have both --key_file and --cert_file\n";
} elsif ($args{SSL_cert_file} and $args{SSL_key_file}) {
  Nimi::Mute->run(%args);
} else {
  Nimi::Mute->run;
}

sub options {
  my $self     = shift;
  my $prop     = $self->{'server'};
  my $template = shift;

  # setup options in the parent classes
  $self->SUPER::options($template);

  $prop->{dir} ||= undef;
  $template->{dir} = \$prop->{dir};

  $prop->{index} ||= undef;
  $template->{index} = \$prop->{index};

  $prop->{password} ||= undef;
  $template->{password} = \$prop->{password};
}

my $dir;
my $max;
my $index;
my $password;

sub post_configure_hook {
  my $self = shift;
  $self->write_help if @ARGV and $ARGV[0] eq '--help';

  $dir = $self->{server}->{dir} || $ENV{NIMI_MUTE_DIR} || '.';
  $max = $self->{server}->{max} || $ENV{NIMI_MUTE_MAX} || 10000;
  $index = $self->{server}->{index} || $ENV{NIMI_MUTE_INDEX} || 'README.md';
  $password = $self->{server}->{password} || $ENV{NIMI_MUTE_PASSWORD} || "";

  $self->log(3, "PID $$");
  $self->log(3, "Host " . ("@{$self->{server}->{host}}" || "*"));
  $self->log(3, "Port @{$self->{server}->{port}}");

  # Note: if you use sudo to run nimi-mute.pl, these options might not work!
  $self->log(4, "--dir says $self->{server}->{dir}\n") if $self->{server}->{dir};
  $self->log(4, "--max says $self->{server}->{max}\n") if $self->{server}->{max};
  $self->log(4, "--index says $self->{server}->{index}\n") if $self->{server}->{index};
  $self->log(4, "--password says $self->{server}->{password}\n") if $self->{server}->{password};
  $self->log(4, "\$NIMI_MUTE_DIR says $ENV{NIMI_MUTE_DIR}\n") if $ENV{NIMI_MUTE_DIR};
  $self->log(4, "\$NIMI_MUTE_MAX says $ENV{NIMI_MUTE_MAX}\n") if $ENV{NIMI_MUTE_MAX};
  $self->log(4, "\$NIMI_MUTE_INDEX says $ENV{NIMI_MUTE_INDEX}\n") if $ENV{NIMI_MUTE_INDEX};
  $self->log(4, "\$NIMI_MUTE_PASSWORD says $ENV{NIMI_MUTE_PASSWORD}\n") if $ENV{NIMI_MUTE_PASSWORD};
  $self->log(3, "Dir is $dir\n");
  $self->log(3, "Max is $max\n");
  $self->log(3, "Index is $index\n");
  $self->log(3, "Password is $password\n");
}

my $usage = << 'EOT';
This server serves a nimi mute site.

It implements Net::Server and thus all the options available to
Net::Server are also available here. Additional options are available:

--dir       - this is the path to the data directory (.)
--index     - this is the default file name (README.md)
--password  - this is the password if you want to enable uploads
--max       - this is the maximum file size for uploads (10000)
--cert_file - the filename containing a certificate in PEM format
--key_file  - the filename containing a private key in PEM format
--port      - the port to listen to, defaults to a random port
--log_level - the log level to use, defaults to 2

Some of these you can also set via environment variables:

NIMI_MUTE_DIR
NIMI_MUTE_INDEX
NIMI_MUTE_PASSWORD
NIMI_MUTE_MAX

For many of the options, more information can be had in the Net::Server
documentation. This is important if you want to daemonize the server. You'll
need to use --pid_file so that you can stop it using a script, --setsid to
daemonize it, --log_file to write keep logs, and you'll need to set the user or
group using --user or --group such that the server has write access to the data
directory.

Example invocation:

perl nimi-mute.pl \
    --port=7079 \
    --pid_file=/tmp/nimi-mute.pid \
    --dir=/tmp/nimi-mute

Run the script and test it:

echo | nc localhost 7079
lynx gopher://localhost:7079

If you want to use SSL, you need to provide PEM files containing certificate and
private key. To create self-signed files, for example:

openssl req -new -x509 -days 365 -nodes -out \
        server-cert.pem -keyout server-key.pem

Make sure the common name you provide matches your domain name!
EOT

run();

sub serve_page {
  my $self = shift;
  my $id = shift;
  if (not -e "$dir/$id") {
    $self->serve_error("file does not exist: '$id'");
  } else {
    $self->log(3, "Serving '$dir/$id'");
    print read_file("$dir/$id");
  }
}

sub serve_main_menu {
  my $self = shift;
  $self->serve_page($index);
}

sub read_page {
  my $self = shift;
  my $pw = <STDIN>;
  $pw =~ s/\s+$//g; # no trailing whitespace
  if ($pw ne $password) {
    $self->serve_error("password mismatch: '$pw'");
  } else {
    my $buf;
    while (1) {
      my $line = <STDIN>;
      if (length($line) == 0) {
	sleep(1); # wait for input
	next;
      } elsif ($line =~ /^\.\r?\n/) {
	last;
      } else {
	$buf .= $line;
	if (length($buf) > $max) {
	  $buf = substr($buf, 0, $max);
	  last;
	}
      }
    }
    $self->log(4, "Received " . length($buf) . " bytes (max is $max): " . uri_escape($buf));
    return $buf;
  }
}

sub write_page {
  my $self = shift;
  my $id = shift;
  my $text = shift;
  my $exists = -e "$dir/$id";
  if (write_file("$dir/$id", $text)) {
    print $exists ? "Updated '$id'\n" : "Created '$id'\n";
  } else {
    $self->serve_error("file '$id' cannot be written: $!");
  }
}

sub append_page {
  my $self = shift;
  my $id = shift;
  my $text = shift;
  my $exists = -e "$dir/$id";
  if (append_file("$dir/$id", $text)) {
    print $exists ? "Appended to '$id'\n" : "Created '$id'\n";
  } else {
    $self->serve_error("file '$id' cannot be written: $!");
  }
}

sub delete_page {
  my $self = shift;
  my $id = shift;
  if (not -e "$dir/$id") {
    $self->serve_error("file does not exist: '$id'");
  } else {
    if (unlink "$dir/$id") {
      $self->log(3, "Deleted '$dir/$id'");
      print "Deleted '$id'\n";
    } else {
      $self->serve_error("file '$id' cannot be deleted: $!");
    }
  }
}

sub serve_error {
  my $self = shift;
  my $error = shift;
  $self->log(3, "Error: $error");
  print("Error: $error\n");
}

sub process_request {
  my $self = shift;

  eval {
    local $SIG{'ALRM'} = sub {
      $self->log(1, "Timeout!");
      die "Timed Out!\n";
    };
    alarm(10); # timeout
    $self->log(4, "Reading selector");
    my $selector = <STDIN>; # one line only
    $self->log(4, "Read selector '$selector'");
    $selector = uri_unescape($selector); # assuming URL-encoded UTF-8
    $selector =~ s/\s+$//g; # no trailing whitespace

    if (not $selector or $selector eq "/") {
      $self->serve_main_menu();
    } elsif ($password and $selector =~ m!^(>+)([^/[:cntrl:]]*)!) {
      my $mode = $1;
      my $id = $2;
      if ($mode eq '>') {
	my $text = $self->read_page();
	if ($text) {
	  $self->write_page($id, $text);
	} else {
	  $self->delete_page($id);
	}
      } elsif ($mode eq '>>') {
	my $text = $self->read_page();
	if ($text) {
	  $self->append_page($id, $text);
	} else {
	  $self->serve_error("nothing to append");
	}
      } else {
	$self->serve_error("invalid mode '$mode'");
      }
    } elsif ($selector =~ m!^([^/[:cntrl:]]*)$!) {
      # no slashes, no control characters
      $self->serve_page($1);
    } else {
      $self->serve_error("invalid selector '$selector'");
    }

    $self->log(4, "Done");
  }
}
