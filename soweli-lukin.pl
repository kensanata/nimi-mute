#!/usr/bin/env perl
# Copyright (C) 2019  Alex Schroeder <alex@gnu.org>
#
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
#
# This is a Simple Text Transfer client webapp, compatible with Nimi Mute.
# Start it up and visit the website it serves.

use Modern::Perl;
use Mojolicious::Lite;
use Text::Markdown 'markdown';
use IO::Socket::IP;
use URI::Find;
use Mojo::Log;
use Encode;

plugin Config => {default => {
  loglevel => 'info',
  logfile => 'soweli-lukin.log', }};

my $log = Mojo::Log->new;
$log->level(app->config('loglevel'));
$log->path(app->config('logfile'));

my $uri_re = URI::Find->new(sub {})->uri_re;

sub self_link {
  my ($c, $id, $text) = @_;
  my $url = $c->param('url');
  $url =~ s/(.*?\/0).*/$1/;
  $id =~ s/ /_/g;
  $url .= $id;
  $url = $c->url_for('main')->query( url => $url );
  return "[$text]($url)";
}

sub rewrite_gopher {
  my $c = shift;
  my $url = shift;
  return $c->url_for('main')->query( url => $url ) if $url =~ /^gopher/;
  return $url;
}

sub process {
  my $c = shift;
  $_ = shift;
  my $buf;
  my $n = 0;
  my $list = 0;
  while (1) {
    if (/\G^(?<type>[01])(?<name>[^\t\n]+)\t(?<selector>[^\t\n]+)\t(?<host>[^\t\n]+)\t(?<port>\d+)\r?\n/cgm) {
      # gopher map: gopher link
      my $text = $+{name};
      my $url = "gopher://$+{host}:$+{port}/$+{type}$+{selector}";
      $url = $c->url_for('main')->query( url => $url );
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)\n";
    } elsif (/\G^h([^\t\n]+)\tURL:([^\t\n]+)\t[^\t\n]*\t[^\t\n]*\r?\n/cgm) {
      # gopher map: hyper link
      my $text = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)\n";
    } elsif (/\G^i([^\t\n]*)\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*\r?\n/cgm) {
      # gopher map: information
      $buf .= "$1\n";
      $list = 0;
    } elsif (/\G^.[^\t\n]*\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*\r?\n/cgm) {
      # gopher map!
      # all other gopher types are not supported
    } elsif (/\G\[($uri_re)\]/cg) {
      $n++;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[[$n]($url)]";
    } elsif (/\G\[($uri_re) ([^]\n]+)\]/cg) {
      my $text = $2;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[$text]($url)";
    } elsif (/\G(\[[^]\n]+\]: $uri_re)/cg) {
      # these references will get handled by Markdown
      $buf .= $1;
    } elsif (/\G($uri_re)/cg) {
      my $text = $1;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[$text]($url)";
    } elsif (/\G\[\[([^]\n]+)\|([^]\n]+)\]\]/cg) {
      $buf .= self_link($c, $1, $2);
    } elsif (/\G\[\[([^]\n]+)\]\]/cg) {
      $buf .= self_link($c, $1, $1);
    } elsif (/\G(\s+)/cg) {
      $buf .= $1;
    } elsif (/\G(\S+)/cg) {
      $buf .= $1;
    } else {
      last;
    }
  }
  return $buf;
}

sub fix {
  # fixing some Text::Markdown weirdness
  my $text = shift;
  $text =~ s!<p><code>!<pre>!g;
  $text =~ s!</code></p>!</pre>!g;
  return $text;
}

sub query {
  my ($c, $host, $port, $selector) = @_;
  $log->info("Querying $host:$port with '$selector'");
  # create client
  my $socket = IO::Socket::IP->new(
    PeerHost => $host,
    PeerPort => $port,
    Type     => SOCK_STREAM,
    Timeout  => 3, )
      or die "Cannot construct client socket: $@";
  $socket->print("$selector\r\n");
  undef $/; # slurp
  my $text = <$socket>;
  $socket->close(); # be explicit
  return '', markdown("No data received from $host:$port using $selector")
      unless length($text) > 0;
  return decode('UTF-8', $text);
}

# return (text, error)
sub get_text {
  my $c = shift;
  my $str = shift;
  return '' unless $str;

  my $url = Mojo::URL->new($str);
  return '', markdown(sprintf("URL scheme must be `gopher` or `gophers`, not %s", $url->scheme || 'empty'))
      unless $url->scheme eq 'gopher' or $url->scheme eq 'gophers';

  my $selector;
  if ($url->path ne '') {
    my $itemtype = substr($url->path, 1, 1);
    return '', markdown(sprintf("Gopher item type must be `0` or `1`, not %s", $itemtype || 'empty'))
	if length($url->path) > 0 and not ($itemtype eq "0" or $itemtype eq "1");

    $selector .= substr($url->path, 2);
    $selector .= "?" . $url->query     if $url->query ne "";
    $selector .= "#" . $url->fragment  if $url->fragment;
  }

  return query($c, $url->host, $url->port || 70, $selector || '');
}

get '/' => sub {
  my $c = shift;
  my $url = $c->param('url');
  my $raw = $c->param('raw');
  my ($md, $error) = get_text($c, $url);
  $md = fix(markdown(process($c, $md))) unless $raw;
  # $md = process($c, $md); $raw = 1;
  $c->render(template => 'index', url => $url, md => $md, error => $error,
	     raw => $raw);
} => 'main';

app->start;

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Soweli Lukin';
<h1>Soweli Lukin</h1>
%= form_for main => begin
%= label_for url => 'URL'
%= text_field url => $url, id => 'url'
%= label_for raw => 'plain text'
%= check_box raw => 1, id => 'raw'
%= submit_button 'Go'
% end
% if ($error) {
<div class="error">
%== $error
</div>
% }
<div class="<%= ($raw ? 'text' : 'markdown') =%>">
%== $md
</div>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<title><%= title %></title>
%= stylesheet '/tarballs.css'
%= stylesheet begin
body {
  padding: 1em;
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
#url { width: 50ex }
.error { font-weight: bold; color: red }
.text { white-space: pre; font-family: mono }
@media only screen and (max-width: 400px) {
  body { padding: 0; }
  h1 { margin-top: 2; margin-bottom: 0; }
  label[for="url"] { display: none; }
  #url { width: 95%; margin-bottom: 10px; }
}
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<%= content %>
<hr>
<p>
<a href="https://alexschroeder.ch/cgit/nimi-mute/about/#soweli-lukin">Soweli Lukin</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
