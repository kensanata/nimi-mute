test:
	jobs=2 prove t

local-test:
	tilix --action=session-add-down --title "Nimi Mute" --command "$(which perl) nimi-mute.pl --port 4000 --log_level 4"
	tilix --action=session-add-down --title "Soweli Lukin" --command "/home/alex/perl5/perlbrew/perls/perl-5.28.1/bin/morbo --mode development --listen http://*:4010 soweli-lukin.pl"
