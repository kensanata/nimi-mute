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
use List::Util qw(max);
use Encode;
use feature 'unicode_strings';

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
  return unless defined $_;
  # the DOS line endings cause needless confusion
  s!\r\n!\n!g;
  # these "malformed" references will get handled by Markdown
  s!\[(\d+,\d+)\]!" " . join(", ", map { "[$_]" } split(/,/, $1))!eg;
  # add a space before numerical references
  s!\b(\[\d+\])! $1!g;
  my $buf;
  my $n = 0;
  my $list = 0;
  while (1) {
    if (/\G^(?<type>[01])(?<name>[^\t\n]+)\t(?<selector>[^\t\n]+)\t(?<host>[^\t\n]+)\t(?<port>\d+)\n/cgm) {
      # gopher map: gopher link
      my $text = $+{name};
      my $url = "gopher://$+{host}:$+{port}/$+{type}$+{selector}";
      $url = $c->url_for('main')->query( url => $url );
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)\n";
    } elsif (/\G^h([^\t\n]+)\tURL:([^\t\n]+)\t[^\t\n]*\t[^\t\n]*\n/cgm) {
      # gopher map: hyper link
      my $text = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)\n";
    } elsif (/\G^i([^\t\n]*)\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*\n/cgm) {
      # gopher map: information
      $buf .= "$1\n";
      $list = 0;
    } elsif (/\G^.[^\t\n]*\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*\n/cgm) {
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
    } elsif (/\G(\[[^]\n]+\]): ($uri_re)/cg) {
      # these references will get handled by Markdown
      my $ref = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "$ref: $url";
    } elsif (/\G(\[[^]\n]+\]) ($uri_re)/cg) {
      # these "malformed" references will get handled by Markdown
      my $ref = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "$ref: $url";
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
  # strip trailing period, if any
  $buf =~ s/^\.$//m;
  return $buf;
}

sub quote_html {
  $_ = shift;
  return unless defined $_;
  s/&/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  s/[\x00-\x08\x0b\x0c\x0e-\x1f]/ /g; # legal xml: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
  return $_;
}

sub quote_ascii_art {
  $_ = shift;
  return unless defined $_;
  my @paragraphs = split(/\n\n+/);
  # compute length of "most lines"
  # my @length = sort { $a <=> $b } map { length } grep /^[[:alnum:]]/, split /\n/;
  # my $short = max $length[$#length] - 20, $length[int($#length * 0.8)];
  for (@paragraphs) {
    my $alphanums = () = /[[:alnum:]]/g;
    my $punctuation = () = /[[:punct:]]/g;
    my $spaces = () = /[[:space:]]/g;
    my $lines = () = /.+/g;
    if ($punctuation + $spaces > $alphanums) {
      my $list_items = () = /^\*.+/gm;
      if ($list_items < $lines) {
	$_ = "<pre>\n$_\n</pre>";
      } else {
	s!^(\* .*)!<code>$1</code>!gm;
      }
    } else {
      # my $max = max map { length } split /\n/;
      # if ($max < $short) {
      # 	$_ = "<pre>\n$_\n</pre>";
      # }
      my $definitions = () = grep /^[[:alpha:]].*:/, split /\n/;
      if ($definitions == $lines
	  or $lines > 4 and $definitions == $lines - 1
	  or $lines > 8 and $definitions == $lines - 2) {
	$_ = "<pre>\n$_\n</pre>";
      }
    }
  }
  return join "\n\n\n", @paragraphs;
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
      or return '', markdown("Cannot connect to $host:$port: $@");
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
  return 'Use a Gopher URL like gopher://alexschroeder.ch to get started' unless $str;

  my $url = Mojo::URL->new($str);
  return '', markdown(sprintf("URL scheme must be `gopher` or `gophers`, not %s", $url->scheme || 'empty'))
      unless $url->scheme eq 'gopher' or $url->scheme eq 'gophers';

  my $selector;
  if ($url->path ne '' and $url->path ne '/') {
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
  # Allow browsers and proxies to cache responses for 60s
  $c->res->headers->cache_control('public, max-age=60');
  my $url = $c->param('url');
  my $raw = $c->param('raw');
  my ($md, $error) = get_text($c, $url);
  $md = quote_html($md);
  if ($raw) {
    $c->render(template => 'index', url => $url, md => $md, error => $error, raw => $raw);
  } else {
    $md = process($c, $md);
    $md = quote_ascii_art($md);
    my $html = $md ? fix(markdown($md)) : '';
    $c->render(template => 'index', url => $url, md => $html, error => $error, raw => $raw);
  }
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
<hr>
<div class="<%= ($raw ? 'text' : 'markdown') =%>">
%== $md
</div>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<title><%= title %></title>
%= stylesheet '/soweli-lukin.css'
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

@@ soweli-lukin.css
body {
  padding: 1em;
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
#url { width: 50ex }
.error { font-weight: bold; color: red }
.text { white-space: pre; font-family: mono }
code { white-space: pre }
@media only screen and (max-width: 400px) {
  body { padding: 0; }
  h1 { margin-top: 2; margin-bottom: 0; }
  label[for="url"] { display: none; }
  #url { width: 95%; margin-bottom: 10px; }
}
