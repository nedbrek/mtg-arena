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

proc makeCardTable {db} {
	$db eval {
		CREATE TABLE cards(
		   id INTEGER PRIMARY KEY,
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
				INSERT INTO cards(name_id, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, abilities)
				VALUES           ($name, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $abilities);
			}
		} elseif {$is_creat} {
			# creatures have power and toughness
			$db eval {
				INSERT INTO cards(name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, power, toughness, abilities)
				VALUES           ($name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $pow, $tough, $abilities);
			}
		} elseif {$is_plane} {
			# planeswalkers have toughness (loyalty)
			$db eval {
				INSERT INTO cards(name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, toughness, abilities)
				VALUES           ($name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $tough, $abilities);
			}
		} elseif {$pow != 0 || $tough != 0} {
			set is_vehicle [expr {$is_arti && [lsearch $sub_type_num 331] != -1}]
			# same as creature
			$db eval {
				INSERT INTO cards(name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, power, toughness, abilities)
				VALUES           ($name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $pow, $tough, $abilities);
			}
		} else {
			# others have cost
			$db eval {
				INSERT INTO cards(name_id, cost, types, sup_types, sub_types, set_name, rarity, set_num, flavor_id, abilities)
				VALUES           ($name, $cost, $type_num, $sup_type_num, $sub_type_num, $set, $rarity, $set_num, $favor, $abilities);
			}
		}
	}
	$db eval {END TRANSACTION}
}

# end namespace
}

