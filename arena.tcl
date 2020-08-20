#!/usr/bin/env tclsh
package require json

set fname [lindex $argv 0]
set f [open $fname]

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
			puts "Inventory: $inv"
		}
	} else {
		puts "$hdr"
	}
}

