package require json
package provide arena_parse 0.1

namespace eval parse {

set loc ""

# parse localizations
proc parseLoc {fname} {
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
	set ::parse::loc [dict get $d_english keys]
}

proc lookupLoc {id} {
	set i [lsearch -index 1 $::parse::loc $id]
	if {$i == -1} {
		return "(loc $id not found)"
	}
	set d [lindex $::parse::loc $i]
	return [dict get $d text]
}

proc lookupLocDb {db id} {
	return [$db onecolumn {SELECT value FROM loc WHERE key=$id}]
}

proc makeLocTable {db} {
	$db eval {
		CREATE TABLE loc(
		   id INTEGER PRIMARY KEY,
		   key INTEGER not null,
		   value TEXT not null
		);
	}
}

proc parseLocToDb {fname db} {
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

	$db eval {BEGIN TRANSACTION}
	foreach l $loc {
		set k [dict get $l id]
		set v [dict get $l text]
		$db eval {
			INSERT INTO loc(key, value)
			VALUES ($k, $v)
		}
	}
	$db eval {END TRANSACTION}
}

proc makeCardTable {db} {
	$db eval {
		CREATE TABLE cards(
		   id INTEGER PRIMARY KEY,
		   card_id INTEGER not null,
		   name_id INTEGER not null,
		   cost TEXT,
		   types TEXT not null,
		   sup_types TEXT not null,
		   sub_types TEXT not null,
		   set_name TEXT not null,
		   rarity INTEGER not null,
		   set_num INTEGER not null,
		   flavor_id INTEGER,
		   power INTEGER,
		   toughness INTEGER,
		   abilities TEXT not null
		);
	}
}

proc cardsToDb {fname db} {
	set f [open $fname]
	set data [read $f]
	close $f

	set d [json::json2dict $data]

	# run through all cards
	$db eval {BEGIN TRANSACTION}
	foreach c $d {
		set card_id      [dict get $c grpid]
		set name         [dict get $c titleId]
		set cost         [dict get $c castingcost]
		set type_num     [dict get $c types]
		set sup_type_num [dict get $c supertypes]
		set sub_type_num [dict get $c subtypes]
		set set          [dict get $c set]
		set rarity       [dict get $c rarity]
		set set_num      [dict get $c collectorNumber]
		set st_id        [dict get $c subtypeTextId]
		set flavor       [dict get $c flavorId]
		set pow          [dict get $c power]
		set tough        [dict get $c toughness]

		set abilities [list]
		foreach a [dict get $c abilities] {
			lappend abilities [dict get $a textId]
		}

		set is_arti  [expr {[lsearch $type_num 1] != -1}]
		set is_creat [expr {[lsearch $type_num 2] != -1}]
		set is_land  [expr {[lsearch $type_num 5] != -1}]
		set is_plane [expr {[lsearch $type_num 8] != -1}]

		if {$flavor eq ""} {
			set flavor 0
		}

		if {$is_land} {
			# land has no cost
			$db eval {
				INSERT INTO cards(card_id, name_id, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, abilities)
				VALUES           ($card_id, $name, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $abilities);
			}
		} elseif {$is_creat} {
			# creatures have power and toughness
			$db eval {
				INSERT INTO cards(card_id, name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, power, toughness, abilities)
				VALUES           ($card_id, $name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $pow, $tough, $abilities);
			}
		} elseif {$is_plane} {
			# planeswalkers have toughness (loyalty)
			$db eval {
				INSERT INTO cards(card_id, name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, toughness, abilities)
				VALUES           ($card_id, $name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $tough, $abilities);
			}
		} elseif {$pow != 0 || $tough != 0} {
			set is_vehicle [expr {$is_arti && [lsearch $sub_type_num 331] != -1}]
			# same as creature
			$db eval {
				INSERT INTO cards(card_id, name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, power, toughness, abilities)
				VALUES           ($card_id, $name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $pow, $tough, $abilities);
			}
		} else {
			# others have cost
			$db eval {
				INSERT INTO cards(card_id, name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, abilities)
				VALUES           ($card_id, $name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $abilities);
			}
		}
	}
	$db eval {END TRANSACTION}
}

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

proc processFile {fname args} {
	set f [open $fname]

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

		foreach {hdrpat linename body} $args {
			if {![regexp $hdrpat $hdr]} {
				continue
			}
			upvar $linename ol
			set ol $l
			set code [catch {uplevel 1 $body} message]
			switch -- $code {
				0 {}
				1 { return -code error -errorinfo $::errorInfo -errorcode $::errorCode $message }
				2 { return -code return $message }
				3 break
				4 continue
				default { return -code $code $message }
			}
		}
	}

	close $f
}

proc superFromInt {t} {
	switch $t {
		1 { return "Basic" }
		2 { return "Legendary" }
	}
	return "(invalid super-type $t)"
}

proc typeFromInt {t} {
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

proc showCard {db card_id} {
	set t [toplevel .t.card$::t_card_num]
	incr ::t_card_num

	$db eval {
		SELECT name_id, cost, types, sup_types, sub_types,
		    set_name, rarity, set_num, flavor_id, power, toughness, abilities
		FROM cards
		WHERE card_id=$card_id
	} {
		set name [parse::lookupLocDb $db $name_id]
		set is_land  [expr {[lsearch $types 5] != -1}]
		set is_creat [expr {[lsearch $types 2] != -1}]
		set is_plane [expr {[lsearch $types 8] != -1}]
		set is_arti  [expr {[lsearch $types 1] != -1}]

		# first row: name and cost
		if {$is_land} {
			grid [label $t.lName -text $name] -row 0 -column 0 -columnspan 2
		} else {
			grid [label $t.lName -text $name] -row 0 -column 0
			grid [label $t.lCost -text [regsub -all "o" $cost " "]] -row 0 -column 1
		}

		# second row: type and set/rarity
		set type_str ""
		foreach st $sup_types {
			append type_str "[superFromInt $st] "
		}
		foreach typ $types {
			append type_str "[typeFromInt $typ] "
		}
		grid [label $t.lType -text $type_str] -row 1 -column 0
		grid [label $t.lSet -text "$set_name $rarity"] -row 1 -column 1

		# main text box
		grid [text $t.tMain] -row 2 -column 0 -columnspan 2
		foreach a $abilities {
			$t.tMain insert end "[parse::lookupLocDb ::db $a]\n"
		}
		if {$flavor_id ne ""} {
			$t.tMain insert end [parse::lookupLocDb ::db $flavor_id]
		}

		# bottom row: set num and pow/tough
		grid [label $t.lSetNum -text $set_num] -row 3 -column 0
		if {$is_creat} {
			grid [label $t.lPowTough -text "$power / $toughness"] -row 3 -column 1
		} elseif {$is_plane} {
			grid [label $t.lPowTough -text $toughness] -row 3 -column 1
		} elseif {$power ne "" || $toughness ne ""} {
			grid [label $t.lPowTough -text "$power / $toughness"] -row 3 -column 1
		}
	}
}

# end namespace
}

