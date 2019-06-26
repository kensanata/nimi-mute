This page documents both a [client](#soweli-lukin), a
[server](#nimi-mute), and a [proxy](#nimi-ilo).

If you're just interested in the web app Gopher client which is a good
alternative to [VF-1](https://github.com/solderpunk/VF-1) for your
mobile devices, feel free to use to 
[start here](https://alexschroeder.ch/soweli-lukin?url=gopher%3A%2F%2Falexschroeder.ch%3A70%2F1map%2FMoku_Pona_Updates).

Nimi Mute
=========

This is a simple file server. It's a return to the old days of the
Internet: send a "selector" and get back some text. That's it.

It's simpler than gopher because we don't care about menus.

Actually, that's not quite true: if you write your Gopher menu by
hand, then it can still be served, and a Gopher client can still read
it. It's just that this wasn't the *intent* when I started the
project.

Examples:

```
# startup server (serving the current directory, and more log messages)
perl nimi-mute.pl --port 7079 --log_level=4
# print the default page (README.md)
echo | nc localhost 7079
# if you have mdcat installed, highlight your Markdown
echo README.md | nc localhost 7079 | mdcat
# if you have lynx installed, use fake gopher
lynx gopher://localhost:7079
# when requesting files, make sure to add a leading zero!
lynx gopher://localhost:7079/0README.md
# prints the source code
echo nimi-mute.pl | nc localhost 7079
# open an interactive session, type a page name at the prompt (10s!)
telnet localhost 7079
# be fancy and start it on port 79
sudo perl nimi-mute.pl --port 79 --log_level=4
# now use finger to read the files!
finger @localhost
finger README.md@localhost
```

Writing
-------

This server also allows users who know the password to *write* files.
Just start your request with the greater-than character, send the
filename, a newline, the password, another newline, then the file
content, and terminate it with a single period on a line by itself,
like in the good old days when `ed` was the standard editor.

That also means that your text file may not contain a line with just
period, obviously.

And just because it was easy to do, two greater-than characters
*append* to a file. It's a bit like shell redirection, right?

Anyway. No filenames starting with `>`, obviously.

Examples:

```bash
# startup server (with password)
perl nimi-mute.pl --port 7079 --log_level=4 --password=admin
# Error: file does not exist: 'Alex'
echo Alex | nc localhost 7079
# Created 'Alex'
echo -e ">Alex\nadmin\nhello\n.\n" | nc localhost 7079
# hello
echo Alex | nc localhost 7079
# Updated 'Alex'
echo -e ">Alex\nadmin\nsay friend\n.\n" | nc localhost 7079
# Appended to 'Alex'
echo -e ">>Alex\nadmin\nand enter\n.\n" | nc localhost 7079
# say friend
# and enter
echo Alex | nc localhost 7079
# or use a file
seq 3 > test
echo . >> test
(echo -e ">Alex\nadmin"; cat test) | nc localhost 7079
# Deleted Alex
echo -e ">Alex\nadmin\n.\n" | nc localhost 7079
```

Options
-------

It implements [Net::Server](https://metacpan.org/pod/Net::Server) and thus
[all the options](https://metacpan.org/pod/Net::Server#DEFAULT-ARGUMENTS-FOR-Net::Server)
available to `Net::Server` are also available here.

Additionally, the following options are used:

```
--dir       - this is the path to the data directory (.)
--index     - this is the default file name (README.md)
--password  - this is the password if you want to enable uploads
--max       - this is the maximum file size for uploads (10000)
--cert_file - the filename containing a certificate in PEM format
--key_file  - the filename containing a private key in PEM format
```

Some of these you can also set via environment variables:

```
NIMI_MUTE_DIR
NIMI_MUTE_INDEX
NIMI_MUTE_PASSWORD
NIMI_MUTE_MAX
```

For many of the options, more information can be had in the
Net::Server documentation. This is important if you want to daemonize
the server. You'll need to use `--pid_file` so that you can stop it
using a script, `--setsid` to daemonize it, `--log_file` to write keep
logs, and you'll need to set the user or group using `--user` or
`--group` such that the server has write access to the data directory.

The most important options for beginners are probably these:

```
--port      - the port to listen to, as it defaults to a random port
--log_level - the log level to use, use 4 instead of the default of 2
```

Securing your Server
--------------------

If you want to use SSL, you need to provide PEM files containing
certificate and private key. To create self-signed files, for example:

```
openssl req -new -x509 -days 365 -nodes -out \
        server-cert.pem -keyout server-key.pem
```

Make sure the common name you provide matches your domain name!

Start server with these two files:

```
perl nimi-mute.pl --port 7079 --log_level=4 \
                  --cert_file=server-cert.pem --key_file=server-key.pem
```

Use `gnutls-cli` to test, using `--insecure` because in this setup,
this is a self-signed key. A small delay is required before send our
request...

```
(sleep 1; echo) | gnutls-cli --insecure melanobombus:7079
```

Limitations
-----------

- Filenames may contain spaces but not newlines as newlines mark the
  end of a request.

- Filenames may not start with a greater-than character because that
  indicates your intention to write to the file.

- Filenames may not end in whitespace as whitespace is trimmed at the
  end of a request.

- Files may not be uploaded if they contain a line with nothing but a
  period on it because that indicates the end of the file.

- There is no simple way to follow links: you either need client
  support, or send new, hand-crafted requests

Soweli Lukin
============

This is a simple text web client. You can give it a Gopher URL and it
will fetch the plain text and interpret it as Markdown, rendering it
as HTML. It's not a complete Gopher client because it only handles
text files and limited gopher menus (item types `0`, `1`, `i` and
`h`).

This is a *Mojolicious* app. You could run it as CGI script but
ideally you'd tell your webserver to act as a proxy to another port on
the same server and have the Mojolicious app run there, either
stand-alone, or via *Hypnotoad* or *Toadfarm*. All of these can be
installed via CPAN.

For development, use *Morbo*. It's part of *Mojolicious*. Here's how
you would invoke it:

```
morbo soweli-lukin.pl
```

This makes the application available locally on port 3000. Use your
web browser to test it. If you make changes to the source code,
*Morbo* automatically reloads it.

Nimi Ilo
========

This is a web proxy. It's a ludicrous idea. Start it up much like the
[server](#nimi-mute). It doesn't support the `dir`, `index` and `max`
options. The idea is that some kind soul sets it up on the net and you
can use your browser to read Gopher pages by setting up a web proxy.

Examples:

```
# startup proxy (with more log messages)
perl nimi-ilo.pl --port 7080 --log_level=4
# use the -x option to tell curl about the proxy
curl -x http://localhost:7080/ http://alexschroeder.ch:70/0Alex_Schroeder
# use an environment variable to tell lynx about the proxy
http_proxy=http://localhost:7080/ lynx http://alexschroeder.ch:70/0Alex_Schroeder
```
