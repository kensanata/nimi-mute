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

use Modern::Perl;
use Test::More;
use Test::Mojo;
use URI::Escape;

require './t/server.pl';

my $port = start_server();

my $target = uri_escape("gopher://localhost:$port/000-plain-text.md");

my $t = Test::Mojo->new(Mojo::File->new('soweli-lukin.pl'));
$t->get_ok('/?url=' . uri_escape("gopher://localhost:$port/001-gopher-text.md"))
    ->status_is(200)
    ->text_is('h1' => 'Soweli Lukin')
    ->text_is('h2' => 'Title')
    ->text_is('p' => 'Hello.')
    ->element_exists("a[href=/?url=$target][text()=000-plain-text.md]")
    ->element_exists("a[href=https://alexschroeder.ch][text()=https://alexschroeder.ch]")
    ->element_exists("a[href=https://alexschroeder.ch/cgit/nimi-mute/][text()=Nimi Mute]")
    ->element_exists("a[href=/?url=$target][text()=some text]")
    ->element_exists("a[href=https://oddmuse.org][text()=1]")
    ->element_exists("a[href=https://emacswiki.org][text()=2]")
    ->text_like('p:nth-of-type(3)' => qr'Notice that we want a space after the word ')
    ->element_exists("a[href=https://communitywiki.org][text()=3]")
    ->element_exists("a[href=https://campaignwiki.org/one][text()=4]")
    ->element_exists("a[href=https://campaignwiki.org/traveller][text()=5]");

# warn $t->get_ok('/?url=' . uri_escape("gopher://localhost:$port/001-gopher-text.md"))->tx->res->to_string;

done_testing();
