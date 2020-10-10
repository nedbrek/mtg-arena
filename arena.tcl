#!/usr/bin/env tclsh
lappend ::auto_path [file dirname $argv0]
package require json
package require sqlite3
package require struct::set
package require arena_parse

### variables
set root [lindex [file volumes] 0]
set path {{Program Files} {Wizards of the Coast} {MTGA} {MTGA_Data} {Logs} {Logs}}
set files [glob -nocomplain [file join $root {*}$path UTC_Log*]]

if {$files eq ""} {
	set fname [lindex $argv 0]
} else {
	set fname [tk_getOpenFile -initialdir [file join $root {*}$path]]
}

sqlite3 db cards.db
puts "Read [db onecolumn {SELECT COUNT(name_id) FROM cards}] cards"

if {[glob -nocomplain inv.db] eq ""} {
	sqlite3 inv_db inv.db
	inv_db eval {
		CREATE TABLE inv(
		   id INTEGER PRIMARY KEY,
		   card_id INTEGER not null,
		   count INTEGER not null
		);
	}
} else {
	sqlite3 inv_db inv.db
}

### parse log
set cur_inv [list]

parse::processFile $fname {PlayerInventory.GetPlayerCards} l {
	set inv [json::json2dict $l]
	if {[dict exists $inv payload]} {
		set inv [dict get $inv payload]
		set last_inv $inv
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
				#puts "Additional cards:"
			}
			set new_inv [list]
			foreach k $diff {
				set e [list $k [dict get $inv $k]]
				lappend new_inv {*}$e
				lappend cur_inv {*}$e
			}
			set inv $new_inv
		} else {
			#puts "Inventory:"
			set cur_inv $inv
		}

		foreach {id cnt} $inv {
			db eval {
				SELECT name_id, set_name, rarity, set_num
				FROM cards
				WHERE card_id = $id
			} {
				set name [parse::lookupLocDb ::db $name_id]
				#puts "$cnt x $name ($set_name $rarity $set_num)"
			}
		}
	}
}
# end of log parsing

inv_db eval {BEGIN TRANSACTION}
foreach {id cnt} $last_inv {
	set data [inv_db eval {
		SELECT id, count
		FROM inv
		WHERE card_id = $id
	}]
	if {$data eq ""} {
		# new card
		# pull data
		db eval {
			SELECT name_id, set_name, rarity, set_num
			FROM cards
			WHERE card_id = $id
		} {
			set name [parse::lookupLocDb ::db $name_id]
			#puts "New card: $cnt x $name ($set_name $rarity $set_num)"
		}

		# add to inventory
		inv_db eval {
			INSERT INTO inv(card_id, count)
			VALUES($id, $cnt)
		}
	} else {
		set db_id   [lindex $data 0]
		set old_cnt [lindex $data 1]
		if {$old_cnt == $cnt} {
			continue
		}

		# pull card data
		db eval {
			SELECT name_id, set_name, rarity, set_num
			FROM cards
			WHERE card_id = $id
		} {
			set name [parse::lookupLocDb ::db $name_id]
			if {$old_cnt > $cnt} {
				puts "Lost card? $cnt x $name ($set_name $rarity $set_num)"
			} elseif {$old_cnt < $cnt} {
				#puts "Add card: $cnt x $name ($set_name $rarity $set_num)"
			}

			inv_db eval {
				UPDATE inv SET count=$cnt WHERE id=$db_id
			}
		}

	}
}
inv_db eval {END TRANSACTION}

