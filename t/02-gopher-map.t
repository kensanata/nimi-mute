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
my $target1 = uri_escape("gopher://localhost:70/000-plain-text.md");
my $target2 = uri_escape("gopher://localhost:70/100-plain-text/menu");

my $t = Test::Mojo->new(Mojo::File->new('soweli-lukin.pl'));
$t->get_ok('/?url=' . uri_escape("gopher://localhost:$port/002-gopher-map"))
    ->status_is(200)
    ->text_is('h1' => 'Soweli Lukin')
    ->element_exists("ul li a[href=/?url=$target1][text()=Plain Text]")
    ->element_exists("ul li a[href=/?url=$target2][text()=Plain Menu]")
    ->element_exists("ul li a[href=http://example.org/wiki][text()=Hypertext]");

# warn $t->get_ok('/?url=' . uri_escape("gopher://localhost:$port/001-gopher-text.md"))->tx->res->to_string;

done_testing();
