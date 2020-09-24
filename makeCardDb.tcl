lappend ::auto_path [file dirname $argv0]
package require arena_parse
package require sqlite3

set root [lindex [file volumes] 0]
set path {{Program Files} {Wizards of the Coast} {MTGA} {MTGA_Data} {Downloads} {Data}}
set files [glob -nocomplain [file join $root {*}$path data_loc*.mtga]]
if {$files eq ""} {
	set config [file join $root {*}$path]
} else {
	set config "config"
}

set cards [glob -nocomplain [file join $config "data_cards_*.mtga"]]
if {$cards eq ""} {
	puts "Can't find card data"
	exit
}

set loc [glob -nocomplain [file join $config "data_loc_*.mtga"]]
if {$loc eq ""} {
	puts "Can't find localization data"
	exit
}

sqlite3 db cards.db

parse::makeCardTable ::db
parse::makeLocTable ::db

parse::cardsToDb $cards ::db
parse::parseLocToDb $loc ::db

