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
# Find an unused port

sub random_port {
  use Errno  qw( EADDRINUSE );
  use Socket qw( PF_INET SOCK_STREAM INADDR_ANY sockaddr_in );

  my $family = PF_INET;
  my $type   = SOCK_STREAM;
  my $proto  = getprotobyname('tcp')  or die "getprotobyname: $!";
  my $host   = INADDR_ANY;  # Use inet_aton for a specific interface

  for my $i (1..3) {
    my $port   = 1024 + int(rand(65535 - 1024));
    socket(my $sock, $family, $type, $proto) or die "socket: $!";
    my $name = sockaddr_in($port, $host)     or die "sockaddr_in: $!";
    setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, 1);
    bind($sock, $name)
	and close($sock)
	and return $port;
    die "bind: $!" if $! != EADDRINUSE;
    print "Port $port in use, retrying...\n";
  }
  die "Tried 3 random ports and failed.\n"
}

my @pids;

# Fork a simple test server
sub start_server {
  my $num = shift||1;
  die "A server already exists: @pids\n" unless @pids < $num;
  my $port = random_port();
  my $pid = fork();
  if (!defined $pid) {
    die "Cannot fork: $!";
  } elsif ($pid == 0) {
    use Config;
    my $secure_perl_path = $Config{perlpath};
    exec($secure_perl_path, "nimi-mute.pl",
	 "--host", "localhost", "--port", $port,
	 "--dir", "t") or die "Cannot exec: $!";
  } else {
    push(@pids, $pid);
    # give the server some time to start up
    sleep 1;
    return $port;
  }
}

END {
  # kill servers
  for my $pid (@pids) {
    kill 'KILL', $pid or warn "Could not kill server $pid";
  }
}

1;
