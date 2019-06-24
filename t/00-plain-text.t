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

use Modern::Perl;
use Test::More;
use Test::Mojo;
use URI::Escape;

require './t/server.pl';

my $port = start_server();

my $t = Test::Mojo->new(Mojo::File->new('soweli-lukin.pl'));
$t->get_ok('/')
    ->status_is(200)
    ->text_is('h1' => 'Soweli Lukin')
    ->element_exists('label[for=url]')
    ->element_exists('input[id=url]');

$t->get_ok('/?url=' . uri_escape("gopher://localhost:$port/000-plain-text.md"))
    ->status_is(200)
    ->text_is('h1' => 'Soweli Lukin')
    ->content_like(qr/This is some text/)
    ->content_like(qr/This is also some text/);

done_testing();
