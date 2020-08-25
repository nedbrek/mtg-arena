package require sqlite3
package require json

# parse localizations
set fname [lindex $argv 0]
set f [open $fname]

set data [read $f]
close $f
set d [json::json2dict $data]

set d_english ""
foreach di $d {
	set lang [dict get $di isoCode]
	if {$lang eq "en-US"} {
		set d_english $di
		break
	}
}

set loc [dict get $d_english keys]
if {0} {
foreach l $loc {
	set id [dict get $l id]
	set txt [dict get $l text]
	puts "$id $txt"
}
}

proc lookupLoc {id} {
	set i [lsearch -index 1 $::loc $id]
	if {$i == -1} {
		return "(loc $id not found)"
	}
	set d [lindex $::loc $i]
	return [dict get $d text]
}

# parse card list
set fname [lindex $argv 1]
set f [open $fname]
set data [read $f]
close $f
set d [json::json2dict $data]

proc printCard {c} {
	set name   [lookupLoc [dict get $c titleId]]
	set cost   [dict get $c castingcost]
	set type   [lookupLoc [dict get $c cardTypeTextId]]
	set type_num [dict get $c types]
	set sup_type_num [dict get $c supertypes]

	set set [dict get $c set]
	set rarity [dict get $c rarity]

	set set_num [dict get $c collectorNumber]
	set set_max [dict get $c collectorMax]

	set st_id [dict get $c subtypeTextId]
	if {$st_id != 0} {
		set subtype [lookupLoc $st_id]
	} else {
		set subtype ""
	}

	set flavor [lookupLoc [dict get $c flavorId]]
	set pow    [dict get $c power]
	set tough  [dict get $c toughness]

	set abilities [list]
	foreach a [dict get $c abilities] {
		lappend abilities [lookupLoc [dict get $a textId]]
	}

	set is_land [expr {[lsearch $type_num 5] != -1}]
	set is_creat [expr {[lsearch $type_num 2] != -1}]
	set is_plane [expr {[lsearch $type_num 8] != -1}]
	set is_arti [expr {[lsearch $type_num 1] != -1}]

	# printing
	if {$is_land} {
		puts "$name"
	} else {
		puts "$name\t[regsub -all "o" $cost " "]"
	}

	if {$subtype ne ""} {
		puts -nonewline "$type - $subtype"
	} else {
		puts -nonewline "$type"
	}
	puts "\t$set $rarity"

	if {0} {
	if {$sup_type_num eq ""} {
		puts "$type_num"
	} else {
		puts "$type_num + $sup_type_num"
	}
	}

	foreach a $abilities {
		puts "$a"
	}
	if {$flavor ne ""} {
		puts "\"$flavor\""
	}

	puts -nonewline "$set_num / $set_max"
	if {$is_creat} {
		puts "\t$pow / $tough"
	} elseif {$is_plane} {
		puts "\t$tough"
	} elseif {$pow != 0 || $tough != 0} {
		set sub_type_num [dict get $c subtypes]
		set is_vehicle [expr {$is_arti && [lsearch $sub_type_num 331] != -1}]
		if {!$is_vehicle} {
			puts "\nNon-creature with pow/tough! $pow / $tough $sub_type_num"
		} else {
			puts "\t$pow / $tough"
		}
	} else {
		puts ""
	}
	puts ""
}

proc nameFromType {t} {
	switch $t {
		1 { return "Artifact" }
		2 { return "Creature" }
		3 { return "Enchantment" }
		4 { return "Instant" }
		5 { return "Land" }
		8 { return "Planeswalker" }
		10 { return "Sorcery" }
	}
	return "(invalid type $t)"
}

proc superFromType {t} {
	switch $t {
		1 { return "Basic" }
		2 { return "Legendary" }
	}
	return "(invalid super-type $t)"
}

proc checkCard {c} {
	set type   [lookupLoc [dict get $c cardTypeTextId]]
	set type_num [dict get $c types]

	if {[dict get $c isToken] == "true"} {
		set name "Token "
	} else {
		set name ""
	}

	# super-type
	set sup_type_num [dict get $c supertypes]
	if {[llength $sup_type_num] > 0} {
		append name [superFromType [lindex $sup_type_num 0]]
		foreach t [lrange $sup_type_num 1 end] {
			append name " [superFromType $t]"
		}
		append name " "
	}

	# TODO: how to detect dual use cards?
	set t0 [lindex $type_num 0]
	set t1 [lindex $type_num 1]
	append name [nameFromType $t0]

	set linked [dict get $c linkedFaces]
	# TODO: note there is a bug in the localization of Instant+Sorcery
	if {$linked ne "" && [llength $type_num] == 2 && ($t0 == 4 || $t0 == 10) && $t0 == $t1} {
		append name " //"
	}

	foreach t [lrange $type_num 1 end] {
		append name " [nameFromType $t]"
	}
	if {$name ne $type} {
		puts "$name != $type"
		printCard $c
	}
}

# run through all cards
foreach c $d {
	printCard $c
	#checkCard $c
}

