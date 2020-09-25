#!/usr/bin/env wish
lappend ::auto_path [file dirname $argv0]
package require sqlite3
package require arena_parse

### globals
set set_names {
	DAR {Dominaria}
	ELD {Throne of Eldraine}
	GRN {Guilds of Ravnica}
	IKO {Ikoria: Lair of Behemoths}
	JMP {Jumpstart}
	RIX {Rivals of Ixalan}
	RNA {Ravnica Allegiance}
	THB {Theros Beyond Death}
	WAR {War of the Spark}
	XLN {Ixalan}
	ZNR {Zendikar Rising}
}

set rare_names {
	"Token"
	"Basic Land"
	"Common"
	"Uncommon"
	"Rare"
	"Mythic"
}

### load stuff
sqlite3 db cards.db
sqlite3 inv_db inv.db
sqlite3 tmp_db :memory:

proc getName {name_id} {
	return [parse::lookupLocDb ::db $name_id]
}
db function getName getName

# unpack collection into tmp db
tmp_db eval {
	CREATE TABLE inv(
	   card_id INTEGER not null,
	   name TEXT not null,
	   count INTEGER not null
	)
}

inv_db eval {
	SELECT card_id, count
	FROM inv
} {
	set name_id [db onecolumn {SELECT name_id FROM cards WHERE card_id=$card_id}]
	set name [parse::lookupLocDb ::db $name_id]
	tmp_db eval {
		INSERT INTO inv(card_id, name, count)
		VALUES($card_id, $name, $count)
	}
}

### gui
wm withdraw .
toplevel .t
bind .t <Destroy> {exit}
wm title .t "Checklist"
pack [frame .t.fAll] -expand 1 -fill both

#### main view
pack [ttk::treeview .t.fAll.tv -yscrollcommand ".t.fAll.vs set"] -side left -expand 1 -fill both
pack [scrollbar .t.fAll.vs -command ".t.fAll.tv yview" -orient vertical] -side left -fill y

set w .t.fAll.tv

set cols {
	{"Name" 126}
	{"Set" 50}
	{"Rarity" 50}
	{"Count" 50}
	{"Total" 50}
	{"Id" 50}
}
set colct ""
for {set i 1} {$i < [llength $cols]} {incr i} { lappend colct $i }
$w configure -columns $colct

$w column #0 -width [lindex $cols 0 1]
$w heading #0 -text [lindex $cols 0 0]
for {set i 1} {$i < [llength $cols]} {incr i} {
	$w heading $i -text [lindex $cols $i 0]
	$w column $i -width [lindex $cols $i 1]
}

##### populate it
set last_set ""
set last_rare ""
set set_node ""
set last_node ""
set last_card ""
db eval {
	SELECT card_id, getName(name_id) as name, rarity, set_name, set_num
	FROM cards
	ORDER BY set_name, rarity, name
} {
	set count [tmp_db onecolumn {SELECT count FROM inv WHERE card_id=$card_id}]
	set total [tmp_db onecolumn {SELECT SUM(count) FROM inv WHERE name=$name}]

	if {$last_set ne $set_name} {
		set set_name $set_name
		# translate
		set real_name $set_name
		if {[dict exists $set_names $set_name]} {
			set real_name [dict get $set_names $set_name]
		}
		set set_node [$w insert {} end -text $real_name]
		set last_node [$w insert $set_node end -text [lindex $rare_names $rarity]]
		set last_card ""
	} elseif {$last_rare != $rarity} {
		set last_node [$w insert $set_node end -text [lindex $rare_names $rarity]]
		set last_card ""
	}

	# check for alternate art
	if {$name eq $last_card} {
		set vals [$w item $prev_item -values]
		set prev_ct [lindex $vals 2]
		if {$prev_ct ne ""} {
			if {$count eq ""} {
				set count $prev_ct
			} else {
				incr count $prev_ct
			}
		}

		set old_set_num [lindex $vals 4]
		set set_num "$old_set_num $set_num"
		set cid [lindex $vals 5]
		lappend cid $card_id

		$w item $prev_item -values [list $set_name $rarity $count $total $set_num $cid]
	} else {
		set prev_item [$w insert $last_node end -text $name -values [list $set_name $rarity $count $total $set_num $card_id]]
	}

	set last_rare $rarity
	set last_set $set_name
	set last_card $name
}

# foreach set
foreach seti [$w children {}] {
	# foreach rarity in the set
	foreach rarei [$w children $seti] {
		set ct 0
		set tct 0
		set tot 0
		foreach cardi [$w children $rarei] {
			incr tot
			set values [$w item $cardi -values]
			set count [lindex $values 2]
			set total [lindex $values 3]
			if {$count ne ""} { incr ct }
			if {$total ne ""} { incr tct }
		}
		$w item $rarei -values [list $ct $tct $tot]
	}
}

