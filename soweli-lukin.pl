#!/usr/bin/env perl
# Copyright (C) 2019-2020  Alex Schroeder <alex@gnu.org>
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
use Mojo::IOLoop;
use URI::Find;
use Mojo::Log;
use List::Util qw(max);
use Encode;
use feature 'unicode_strings';
use IO::Socket::SSL qw(SSL_VERIFY_NONE SSL_VERIFY_PEER);

plugin Config => {default => {
  loglevel => 'debug',
  logfile => '', }};

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
  my $tls = $c->param('tls');
  my %params = (url => $url);
  $params{tls} = 1 if $tls;
  return $c->url_for('main')->query( %params ) if $url =~ /^(gopher|gemini)/;
  return $url;
}

sub process {
  my $c = shift;
  $_ = shift;
  my $scheme = shift;
  my $host = shift;
  my $port = shift;
  return unless defined $_;
  my $debug = $c->param('debug');
  # the DOS line endings cause needless confusion
  s!\r\n!\n!g;
  # Gemini
  s!^20 text/(plain|gemini).*\n!!;
  # these "malformed" references will get handled by Markdown
  s!\[(\d+,\d+)\]!" " . join(", ", map { "[$_]" } split(/,/, $1))!eg;
  # add a space before numerical references
  s!\b(\[\d+\])! $1!g;
  # remove the trailing underscore after numerical references
  s!(\[\d+\])_! $1!g;
  # fix markup for the references at the end, too
  s!^\.\. (\[\d+\]) : __!$1:!gm;
  my $buf = '';
  my $n = 0;
  my $list = 0;
  my $blockquote = 0;
  while (1) {
    if (/\G^(?<type>[01])(?<name>[^\t\n]*)\t(?<selector>[^\t\n]*)\t(?<host>[^\t\n]*)\t(?<port>\d*).*\n/cgm) {
      # gopher map: gopher link (name is mandatory, all other fields are optional, including extra fields)
      my $text = $+{name};
      my $scheme = 'gopher';
      my $tls = $c->param('tls');
      if ($tls and $+{host} eq $host and $+{port} eq $port) {
	# if we're on the same server, use the secure scheme
	$scheme .= 's';
      }
      my $url = rewrite_gopher($c, "$scheme://$+{host}:$+{port}/$+{type}$+{selector}");
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)";
      if ($tls and ($+{host} ne $host or $+{port} ne $port)) {
	# if the link goes elsewhere, warn the user
	$buf .= ' 🔓';
      }
      $buf .= "¹" if $debug;
      $buf .= "\n";
    } elsif (/\G^h([^\t\n]+)\tURL:([^\t\n]+)\t[^\t\n]*\t[^\t\n]*.*\n/cgm) {
      # gopher map: hyper link
      my $text = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)";
      $buf .= "²" if $debug;
      $buf .= "\n";
    } elsif (/\G^i([^\t\n]*)\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*.*\n/cgm) {
      # gopher map: information
      $buf .= "\n" if $list;
      $buf .= $1;
      $list = 0;
      $buf .= "³" if $debug;
      $buf .= "\n";
    } elsif (/\G^=>[ \t]*(?<url>\S+)[ \t]*(?<text>.*)\n/cgm) {
      # gemini link!
      # => gemini://example.org/
      # => gemini://example.org/ An example link
      # => gemini://example.org/foo Another example link at the same host
      # =>gemini://example.org/bar Yet another example link at the same host
      # => foo/bar/baz.txt A relative link
      # => gopher://example.org:70/1 A gopher link
      my $text = $+{text} || $+{url};
      my $url = Mojo::URL->new($+{url});
      $url->base(Mojo::URL->new($c->param('url')));
      $url = rewrite_gopher($c, $url->to_abs);
      $buf .= "\n" unless $list++;
      $buf .= "* [$text]($url)";
      $buf .= "¹⁷" if $debug;
      $buf .= "\n";
    } elsif (/\G^.[^\t\n]*\t[^\t\n]*\t[^\t\n]*\t[^\t\n]*\n.*/cgm) {
      # gopher map!
      # all other gopher types are not supported (must come after gemini links)
      $buf .= "⁴" if $debug;
    } elsif (/\G(\[[^]]+\]\([^]\s]+\))/cg) {
      # markdown links are passed through as-is: [text](URL)
      $buf .= $1;
      $buf .= "¹⁸" if $debug;
    } elsif (/\G\[($uri_re)\]/cg) {
      $n++;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[[$n]($url)]";
      $buf .= "⁵" if $debug;
    } elsif (/\G\[($uri_re) ([^]\n]+)\]/cg) {
      # wikipedia style links: [URL text]
      my $text = $2;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[$text]($url)";
      $buf .= "⁶" if $debug;
    } elsif (/\G(\[[^]\n]+\]): ($uri_re)/cg) {
      # these references will get handled by Markdown
      my $ref = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "$ref: $url";
      $buf .= "¹⁶" if $debug;
    } elsif (/\G(\[[^]\n]+\]) ($uri_re)/cg) {
      # these "malformed" references will get handled by Markdown
      my $ref = $1;
      my $url = rewrite_gopher($c, $2);
      $buf .= "$ref: $url";
      $buf .= "⁷" if $debug;
    } elsif (/\G($uri_re)/cg) {
      # free URLs
      my $text = $1;
      my $url = rewrite_gopher($c, $1);
      $buf .= "[$text]($url)";
      $buf .= "⁸" if $debug;
    } elsif (/\G\[\[([^]\n]+)\|([^]\n]+)\]\]/cg) {
      # internal links [[page|text]]
      $buf .= self_link($c, $1, $2);
      $buf .= "⁹" if $debug;
    } elsif (/\G\[\[([^]\n]+)\]\]/cg) {
      # internal links [[page]]
      $buf .= self_link($c, $1, $1);
      $buf .= "¹⁰" if $debug;
    } elsif (/\G\[(\/?)quote\]/cg) {
      # bbCode blockquotes
      # [quote]
      # foo
      # [/quote]
      $buf .= "<$1blockquote>";
      $buf .= "¹¹" if $debug;
    } elsif (/\G"""/cg) {
      # Markdown-like fencing for blockquote
      # """
      # foo
      # """
      $buf .= $blockquote ? "</blockquote>" :  "<blockquote>";
      $blockquote = not $blockquote;
      $buf .= "¹²" if $debug;
    } elsif (/\G^```\n(.*?\n)```/cgms) {
      # Markdown-like fencing for code
      # ```
      # foo
      # ```
      $buf .= "<pre>$1</pre>";
      $buf .= "¹³" if $debug;
    } elsif (/\G^---\n((?:.*:.*\n)+)---/cgm) {
      # YAML formatted meta-data
      # ---
      # foo: bar
      # ---
      # gopher://sdf.org:70/0/users/frrobert/GopherBlog/VimwikiontheCommandline.wiki
      $buf .= "<table>"
	  . (join "",
	     map { "<tr>$_</tr>" }
	     map { join "", map { "<td>$_</td>" } split /: */, $_, 2 }
	     split "\n", $1)
	  . "</table>";
      $buf .= "¹⁴" if $debug;
    } elsif (/\G^---\n(.*?)\n---/cgms) {
      # Malformed YAML meta data?
      # ---
      # foo bar
      # ---
      $buf .= "<pre>$1</pre>";
      $buf .= "¹⁵" if $debug;
    } elsif (/\G^(#\w+(?:[ \t]+#\w+)*)/cgm) {
      # Protect a line of hashtags from being treated as H1 headers
      $buf .= "<span class=\"tags\">$1</span>";
      $buf .= "¹⁹" if $debug;
    } elsif (/\G(\s+)/cg) {
      # stretches of whitespace
      $buf .= $1;
    } elsif (/\G^(\w+)/cgm) {
      # stretches of word constituents at the beginning of a line means no list!
      $list = 0;
      $buf .= $1;
      $buf .= "⁰" if $debug;
    } elsif (/\G(\w+)/cg) {
      # stretches of word constituents
      $buf .= $1;
      $buf .= "⁰" if $debug;
    } elsif (/\G(.)/cgm) {
      # Punctuation and the like is handled one character at a time such that we
      # can handle things like [quote](a quote)[/quote]. If we handled multiple
      # punctuation characters at once, the parser would skip over ")[" and not
      # recognize "[/quote]".
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
  my @paragraphs = split(/\n\s*\n/);
  # first, let's detect headlines lacking a newline
  # gopher://gopher.club:70/1/users/ayaron/
  for (@paragraphs) {
    # remove leading space for entire paragraph
    s/^ //gm if /^( .*\n?)+$/;
    # add empty line after heading if required
    s/^(.+)\n(=+)\n\b/
	if (length($1) == length($2)) {
          "$1\n$2\n\n"
        } else {
          "$1\n$2\n"
        }/e;
  }
  $_ = join "\n\n", @paragraphs;
  # actual ASCII art detection
  @paragraphs = split(/\n\s*\n/);
  # compute length of "most lines"
  # my @length = sort { $a <=> $b } map { length } grep /^[[:alnum:]]/, split /\n/;
  # my $short = max $length[$#length] - 20, $length[int($#length * 0.8)];
  for (@paragraphs) {
    my $alphanums = () = /[[:alnum:]]/g;
    my $punctuation = () = /[[:punct:]]/g;
    my $spaces = () = /[[:space:]]/g;
    my $lines = () = /.+/g;
    if ($lines == 2 and (/\n-+$/ or /\n=+$/)) {
      # Do nothing: these are Markdown headings.
    } elsif ($punctuation + $spaces > $alphanums) {
      # When counting list items, make sure we don't count ** as a list item.
      # gopher://gopher.floodgap.com/
      # Make sure we require a space after the asterisk.
      # gopher://gopher.prismdragon.net/
      if ($lines == (() = /^\* .*/gm)) {
	# If all the ASCII art looks like it could be list items, then let's
	# wrap it all in a code tag (such that Markdown still renders links).
	# Adding the class here prevents fix() from touching it. Examples:
	# gopher://gopher.club:70/1/users/gallowsgryph/
	# gopher://gopher.club:70/1/users/xiled/
	s!^(\* .*)!<code class="list">$1</code><br>!gm;
      } else {
	# If there's a lot of punctiation compared to alphanumerics, it's probably
	# ASCII art. Example: gopher://circumlunar.space:70/1/~cmccabe/
	$_ = quote_html $_;
	$_ = qq{<pre class="ascii">\n$_\n</pre>};
      }
    } elsif ($lines == (() = /^\*[^*].*   /gm)) {
      # If we have a list and every list item has multiple spaces in them,
      # chances are it's a directory of files with dates and sizes.
      s!^(\* .*)!<code class="list">$1</code><br>!gm;
    } else {
      # my $max = max map { length } split /\n/;
      # if ($max < $short) {
      # 	$_ = "<pre>\n$_\n</pre>";
      # }
      # Definition lists and the like. Examples:
      # gopher://sdf.org:70/1/users/trnslts/feels/2019-05-13
      # gopher://sdf.org:70/0/users/dbucklin/posts/diction.txt
      my $definitions = () = grep /^[[:alpha:]].*:\s+.+/, split /\n/;
      if ($lines > 1
	  and ($definitions == $lines
	       or $lines > 4 and $definitions == $lines - 1
	       or $lines > 8 and $definitions == $lines - 2)) {
	my $table = "<table>";
	my $col1 = 1;
	for my $term (split /^([[:alpha:]].*):\s+/m) {
	  if ($col1) {
	    next unless $term; # first field is always empty
	    $table .= "<tr><td>$term</td>";
	  } else {
	    $table .= "<td>$term</td></tr>";
	  }
	  $col1 = not $col1;
	}
	$table .= "</table>";
	$_ = $table;
	# $_ = qq{<pre class="definitions">\n$_\n</pre>};
      }
    }
    # my @alnums = /[[:alnum:]]/g;
    # $_ .= "$punctuation + $spaces > $alphanums";
  }
  return join "\n\n", @paragraphs;
}

sub fix {
  # Fixing some Text::Markdown weirdness. What I think should be pre is getting
  # rendered as p code. Replacing them as matched pairs because we sometimes use
  # code with a class to circumvent this fix, and in this case we want to
  # prevent the "fixing" of the closing tags, too.
  my $text = shift;
  $text =~ s!<p><code>(.*?)</code></p>!<pre class="fix">$1</pre>!gs;
  # Remove trailing two dashes left if the link section has been removed by
  # Markdown processing. Example:
  # gopher://lambda.icytree.org:70/0/phlog/2019-06-15-Dwarves-and-Gophers.txt
  $text =~ s!<p>--\s*</p>\s*$!!;
  return $text;
}

sub query {
  my ($c, $scheme, $host, $port, $selector, $tls, $verify) = @_;
  $log->debug("Querying $host:$port with '$selector' (TLS=$tls)");
  my $buf = '';
  my $id = Mojo::IOLoop->client({address => $host, port => $port, tls => $tls, tls_verify => $verify} => sub {
    my ($loop, $err, $stream) = @_;
    return handle($c, '', markdown("Unable to connect to $host:$port")) unless $stream;
    $stream->on(read => sub {
      my ($stream, $bytes) = @_;
      # $log->debug("Received " . length($bytes) . " bytes");
      $buf .= $bytes });
    $stream->on(close => sub {
      my $loop = shift;
      $log->debug("Stream closed: " . length($buf) . " bytes received");
      # this is the only call to handle that isn't reporting an error!
      handle($c, decode('UTF-8', $buf), '', $scheme, $host, $port)});
    $log->debug("Connected to $host:$port and sending '$selector'");
    $stream->write("$selector\r\n")});
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub handle {
  my $c = shift;
  my $md = shift;
  my $error = shift;
  my $scheme = shift;
  my $host = shift;
  my $port = shift;
  $error = markdown($error) if $error;
  my $url = $c->param('url');
  if ($c->param('raw')) {
    $md = quote_html($md);
    $c->render(template => 'index', url => $url, md => $md, error => $error, raw => 1);
  } else {
    my $debug = $c->param('debug');
    $md = process($c, $md, $scheme, $host, $port) unless $debug >= 5;
    $md = quote_ascii_art($md) unless $debug >= 4;
    $md = markdown($md) unless $debug >= 3;
    $md = fix($md) unless $debug >= 2;
    $c->render(template => 'index', url => $url, md => $md, error => $error, raw => undef);
  }
}

# return (text, error)
sub get_text {
  my $c = shift;
  my $str = shift;
  return handle($c, 'Use a Gopher URL like gopher://localhost:4000 to get started')
      if not $str and $c->app->mode eq "development";
  return handle($c, 'Use a Gopher URL like gopher://alexschroeder.ch '
		. 'or gophers://alexschroeder.ch:7443 to get started, '
		. 'or a Gemini URL like gemini://alexschroeder.ch')
      if not $str;
  $log->info("Getting $str for " . $c->tx->req->headers->header('X-Forwarded-For'));

  my $url = Mojo::URL->new($str);
  if (not $url->scheme) {
    $url = Mojo::URL->new("gopher://$str");
    $c->param('url', $url);
  }
  return handle($c, '', sprintf("URL scheme must be `gopher` or `gophers`, not %s", $url->scheme))
      unless $url->scheme eq 'gopher' or $url->scheme eq 'gophers' or $url->scheme eq 'gemini';

  my $tls = $c->param('tls') || '0';

  return handle($c, '', sprintf("Please uncheck the TLS checkbox before following a `gopher` link"))
      if $tls and $url->scheme eq 'gopher';

  my $verify = SSL_VERIFY_PEER; # check server certificates
  if (not $tls and $url->scheme eq 'gophers') {
    $tls = 1;
    $c->param('tls', 1);
    $log->info("Upgrading $str to TLS");
  }
  if ($url->scheme eq 'gemini') {
    $tls = 1;
    $c->param('tls', 1);
    $verify = SSL_VERIFY_NONE; # no check for server certificate
    $log->info("Disabling certificate verification for $str");
  }

  my $port = $url->port;
  $port ||= 70 if $url->scheme eq 'gopher';
  $port ||= 1965 if $url->scheme eq 'gemini';

  my $selector;
  if ($url->scheme eq 'gopher' or $url->scheme eq 'gophers') {
    if ($url->path ne '' and $url->path ne '/') {
      my $itemtype = substr($url->path, 1, 1);
      return handle($c, '', sprintf("Gopher item type must be `0` or `1`, not %s",
				    $itemtype || 'empty'))
	  if length($url->path) > 0 and not ($itemtype eq "0" or $itemtype eq "1");

      $selector .= substr($url->path, 2);
      $selector .= "?" . $url->query     if $url->query ne "";
      $selector .= "#" . $url->fragment  if $url->fragment;
    }
  } elsif ($url->scheme eq 'gemini') {
    $selector = $url;
  }

  query($c, $url->scheme, $url->host, $port, $selector || '', $tls, $verify);
}

get '/' => sub {
  my $c = shift;
  # Allow browsers and proxies to cache responses for 60s
  $c->res->headers->cache_control('public, max-age=60');
  get_text($c, $c->param('url'));
  $c->render_later;
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
%= label_for tls => 'TLS'
%= check_box tls => 1, id => 'tls'
% if (app->mode eq 'development') {
%= label_for debug => 'debug'
%= check_box debug => 1, id => 'debug'
% }
%= submit_button 'Go'
% end
% if ($error) {
<div class="error">
%== $error
</div>
% } else {
<hr>
% }
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
<a href="https://alexschroeder.ch/software/Nimi_Mute">Issues</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>

@@ soweli-lukin.css
body {
  padding: 1em;
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
td { padding-right: 1em }
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
