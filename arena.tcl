#!/usr/bin/env tclsh
package require json
package require sqlite3
package require struct::set

### variables
set config "config"

proc loadConfig {config} {
	set loc [glob -nocomplain [file join $config "data_loc_*.mtga"]]
	set cards [glob -nocomplain [file join $config "data_cards_*.mtga"]]
	if {$loc eq "" || $cards eq ""} {
		return 1
	}

	# parse localizations
	set f [open $loc]
	set loc_raw [read $f]
	close $f
	set loc_d [json::json2dict $loc_raw]

	set d_english ""
	foreach di $loc_d {
		set lang [dict get $di isoCode]
		if {$lang eq "en-US"} {
			set d_english $di
			break
		}
	}

	set loc [dict get $d_english keys]
	foreach l $loc {
		set id [dict get $l id]
		set ::local_str($id) [dict get $l text]
	}
	unset loc
	unset loc_d
	unset loc_raw

	# parse card definitions
	set f [open $cards]
	set cards_raw [read $f]
	close $f
	set cards_d [json::json2dict $cards_raw]

	foreach c $cards_d {
		set id [dict get $c grpid]
		set ::cards($id) $c
	}
	unset cards_d
	unset cards_raw
	puts "Read [array size ::cards] cards"

	return 0
}

### helper functions
proc countBraces {l} {
	set brace_count 0
	foreach c [split $l ""] {
		if {$c eq "\{"} {
			incr brace_count
		} elseif {$c eq "\}"} {
			incr brace_count -1
		}
	}
	return $brace_count
}

### parse log
loadConfig $config

set cur_inv [list]

set fname [lindex $argv 0]
set f [open $fname]

# foreach line
for {set l [gets $f]} {![eof $f]} {
		set prev_line $l
		set l [gets $f]
	} {
	set first_brace [string first "\{" $l]
	if {$first_brace == -1} {
		continue
	}

	set brace_count [countBraces $l]
	while {![eof $f] && $brace_count > 0} {
		set nextline [gets $f]
		append l $nextline
		incr brace_count [countBraces $nextline]
	}

	if {$brace_count < 0} {
		puts "Underflow!"
	}

	if {[string index $l 0] eq "\{"} {
		set hdr $prev_line
	} else {
		set hdr [string range $l 0 $first_brace-1]
		set l [string range $l $first_brace end]
	}

	if {[regexp {PlayerInventory.GetPlayerCards} $hdr]} {
		if {![regexp {PlayerInventory.GetPlayerCardsV3} $hdr]} {
			puts "New inventory version: $hdr"
		}

		set inv [json::json2dict $l]
		if {[dict exists $inv payload]} {
			set inv [dict get $inv payload]
			if {$cur_inv ne ""} {
				# strip out counts
				set k_inv [dict keys $inv]
				set k_cur [dict keys $cur_inv]

				set diff [struct::set symdiff $k_inv $k_cur]
				if {$diff eq ""} {
					continue
				}
				set new_cards [struct::set difference $k_inv $k_cur]
				if {$new_cards ne $diff} {
					puts "Cards lost?"
				} else {
					puts "Additional cards:"
				}
				set new_inv [list]
				foreach k $diff {
					set e [list $k [dict get $inv $k]]
					lappend new_inv {*}$e
					lappend cur_inv {*}$e
				}
				set inv $new_inv
			} else {
				puts "Inventory:"
				set cur_inv $inv
			}

			foreach {id cnt} $inv {
				set c $::cards($id)
				set name $::local_str([dict get $c titleId])
				set rarity [dict get $c rarity]
				set set [dict get $c set]
				set set_num [dict get $c collectorNumber]
				puts "$cnt x $name ($set $rarity $set_num)"
			}
		}
	} else {
		puts "$hdr $l"
	}
}

