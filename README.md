Nimi Mute
=========

This is a simple file server. It's a return to the old days of the
Internet: send a "selector" and get back some text. That's it.

It's simpler than gopher because we don't care about menus.

It's simpler than the web because we don't have request headers.

It's simpler than finger because we don't have structured information.

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
This uses ASCII control characters:

- SOH (start of heading) starts the process
- what follows is the page name
- the page name is terminated by a newline
- trailing whitespace is trimmed (including \r)
- then there's the password you need to provide
- the password is terminated by a newline
- trailing whitespace is trimmed (including \r)
- anything else is skipped until the text begins
- STX (start of text) begins the text
- the text goes in here
- ETX (end of text) ends the text

SOH, STX and ETX are the first three ASCII control characters: ^A, ^B
and ^C, also known as x01, x02, and x03. You can `echo` them from the
shell using backslash escapes, which you have to enable using `-e`.

Examples:

```
# startup server (with pasword)
perl nimi-mute.pl --port 7079 --log_level=4 --password=admin
# Error: file does not exist: 'Alex'
echo Alex | nc localhost 7079
# Created 'Alex'
echo -e "\01Alex\nadmin\n\02say friend\n\03" | nc localhost 7079
# say friend
echo Alex | nc localhost 7079
# Updated 'Alex'
echo -e "\01Alex\nadmin\n\02say friend\nand enter\n\03" | nc localhost 7079
# say friend
# and enter
echo Alex | nc localhost 7079
# or use a file
seq 3 > test
(echo -ne "\01Alex\nadmin\n\02"; cat test; echo -e "\03") | nc localhost 7079
```

In that last example, the first echo uses `-n` to avoid prepending a
newline to the page.

Options
-------

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

For many of the options, more information can be had in the
Net::Server documentation. This is important if you want to daemonize
the server. You'll need to use --pid_file so that you can stop it
using a script, --setsid to daemonize it, --log_file to write keep
logs, and you'll need to set the user or group using --user or --group
such that the server has write access to the data directory.

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

- Filenames may not end in whitespace as whitespace is trimmed at the
  end of a request.

- There is no simple way to follow links: you either need client
  support, or send new, hand-crafted requests
