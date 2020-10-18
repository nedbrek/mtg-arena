#!/usr/bin/env wish
lappend ::auto_path [file dirname $argv0]
package require json
package require sqlite3
package require arena_parse
package require Itcl

proc copyTree {w} {
	clipboard clear
	set items [$w selection]
	foreach i $items {
		clipboard append "[$w item $i -text]\t[join [$w item $i -values] \t]\n"
	}
}
bind Treeview <Control-c> {copyTree %W}

wm withdraw .

### class definitions
itcl::class Logger {
	method startDeck {cards} { puts "Pure virtual called!"; exit }
	method startGame {players} { puts "Pure virtual called!"; exit }
	method dieRolls {rolls} { puts "Pure virtual called!"; exit }
	method setPhase {player turn_no phase step} { puts "Pure virtual called!"; exit }
	method addLine {verb name card_id} { puts "Pure virtual called!"; exit }
	method hitPlayer {card_name tgt damage life} { puts "Pure virtual called!"; exit }
	method hitCard {card_name tgt damage} { puts "Pure virtual called!"; exit }
	method gameOver {winner reason {p_life {}}} { puts "Pure virtual called!"; exit }
}

itcl::class ConsoleLogger {
	inherit Logger

	destructor {
		exit
	}

	method startDeck {cards} {
		# TODO: make a "log level" to dump this info
	}

	method startGame {players} {
		puts -nonewline "\nMatch between"
		set first 1
		foreach p $players {
			set name [dict get $p "playerName"]
			set seat [dict get $p "systemSeatId"]
			if {!$first} {
				puts -nonewline " and"
			}
			set first 0
			puts -nonewline " $name (player $seat)"
		}
		puts ""
	}

	method dieRolls {rolls} {
		set txt ""
		foreach r $rolls {
			append txt " seat [dict get $r "systemSeatId"]"
			append txt " roll [dict get $r "rollValue"]"
		}
		puts "Start game:$txt"
	}

	method setPhase {player turn_no phase step} {
		if {$step ne ""} {
			puts "Player $player, turn $turn_no, $phase, $step"
		} else {
			puts "Player $player, turn $turn_no, $phase"
		}
	}

	method addLine {verb name card_id} {
		puts "   $verb $name"
	}

	method hitPlayer {card_name tgt damage life} {
		puts "   $card_name hits player $tgt for $damage, life is $life"
	}

	method hitCard {card_name tgt damage} {
		puts "   $card_name hits $tgt for $damage"
	}

	method gameOver {winner reason {p_life {}}} {
		if {$reason eq "ResultReason_Game"} {
			puts "Game over: Player $winner wins"
		} elseif {$reason eq "ResultReason_Concede"} {
			puts "Game over: Player $winner wins (other player concedes)"
		} else {
			puts "Game over: Player $winner wins, $reason"
		}

		if {$p_life ne ""} {
			puts "Life totals: $p_life"
		}
	}
}

set t_card_num 0

proc selectCardFromView {w} {
	set w .t.fAll.tv
	set cur [$w selection]
	set values [$w item $cur -values]
	set card_id [lindex $values 0]
	parse::showCard ::db $card_id
}

itcl::class WidgetLogger {
	inherit Logger

	variable game_row ""
	variable insert_row ""

	constructor {} {
		toplevel .t
		wm title .t "Game Log"
		bind .t <Destroy> {exit}

		set w .t.fAll.tv
		pack [frame .t.fAll] -expand 1 -fill both
		pack [ttk::treeview $w -yscrollcommand ".t.fAll.vs set"] -side left -expand 1 -fill both
		pack [scrollbar .t.fAll.vs -command "$w yview" -orient vertical] -side left -fill y

		bind $w <Double-1> [list selectCardFromView %W]
	}

	method startDeck {cards} {
		set w .t.fAll.tv
		set r [$w insert $game_row end -text "Deck"]
		set prev_card ""
		set prev_item ""
		set prev_cnt 0
		foreach c $cards {
			set name_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$c}]
			set name [parse::lookupLocDb db $name_id]
			if {$name eq $prev_card} {
				incr prev_cnt
				$w item $prev_item -text "$name x $prev_cnt"
			} else {
				set prev_card $name
				set prev_item [$w insert $r end -text $name -values $c]
				set prev_cnt 1
			}
		}
	}

	method startGame {players} {
		set first 1
		set txt ""
		foreach p $players {
			set name [dict get $p "playerName"]
			set seat [dict get $p "systemSeatId"]
			if {!$first} {
				append txt ", "
			}
			set first 0
			append txt "$name (player $seat)"
		}
		set w .t.fAll.tv
		set game_row [$w insert {} end -text $txt]
	}

	method dieRolls {rolls} {
		set txt ""
		foreach r $rolls {
			append txt "seat [dict get $r "systemSeatId"] "
			append txt "roll [dict get $r "rollValue"] "
		}
		set w .t.fAll.tv
		$w insert $game_row end -text "$txt"
	}

	method setPhase {player turn_no phase step} {
		set txt ""
		if {$step ne ""} {
			set txt "Player $player, turn $turn_no, $phase, $step"
		} else {
			set txt "Player $player, turn $turn_no, $phase"
		}
		set w .t.fAll.tv
		set insert_row [$w insert $game_row end -text "$txt" -open 1]
	}

	method addLine {verb name card_id} {
		set w .t.fAll.tv
		$w insert $insert_row end -text "$verb $name" -values $card_id
	}

	method hitPlayer {card_name tgt damage life} {
		set w .t.fAll.tv
		$w insert $insert_row end -text "$card_name hits player $tgt for $damage, life is $life"
	}

	method hitCard {card_name tgt damage} {
		set w .t.fAll.tv
		$w insert $insert_row end -text "$card_name hits $tgt for $damage"
	}

	method gameOver {winner reason {p_life {}}} {
		set w .t.fAll.tv
		set txt ""
		if {$reason eq "ResultReason_Game"} {
			set txt "Game over: Player $winner wins"
		} elseif {$reason eq "ResultReason_Concede"} {
			set txt "Game over: Player $winner wins (other player concedes)"
		} else {
			set txt "Game over: Player $winner wins, $reason"
		}
		$w insert $insert_row end -text $txt

		if {$p_life ne ""} {
			$w insert $insert_row end -text "Life totals: $p_life"
		}
	}
}

### variables
if {$argv ne ""} {
	set fname [lindex $argv 0]
	set logger [ConsoleLogger #auto]
} else {
	set root [lindex [file volumes] 0]
	set path {{Program Files} {Wizards of the Coast} {MTGA} {MTGA_Data} {Logs} {Logs}}
	set fname [tk_getOpenFile -initialdir [file join $root {*}$path]]
	set logger [WidgetLogger #auto]
}

sqlite3 db cards.db
puts "Read [db onecolumn {SELECT COUNT(name_id) FROM cards}] cards"

### helper functions
proc dGet {d k} {
	if {[dict exists $d $k]} {
		return [dict get $d $k]
	}
	return ""
}

### parse log
set game_objs [dict create]
set p_life [dict create]

set ignore_msgs {
	"ClientMessageType_AssignDamageResp"
	"ClientMessageType_CastingTimeOptionsResp"
	"ClientMessageType_ChooseStartingPlayerResp"
	"ClientMessageType_ConcedeReq"
	"ClientMessageType_DeclareAttackersResp"
	"ClientMessageType_DeclareBlockersResp"
	"ClientMessageType_GetSettingsReq"
	"ClientMessageType_GroupResp"
	"ClientMessageType_MulliganResp"
	"ClientMessageType_OptionalActionResp"
	"ClientMessageType_PerformAutoTapActionsResp"
	"ClientMessageType_SearchResp"
	"ClientMessageType_SelectNResp"
	"ClientMessageType_SelectReplacementResp"
	"ClientMessageType_SelectTargetsResp"
	"ClientMessageType_SetSettingsReq"
	"ClientMessageType_SubmitAttackersReq"
	"ClientMessageType_SubmitBlockersReq"
	"ClientMessageType_SubmitTargetsReq"
}

set ignore_actions {
	"ActionType_Pass"
	"ActionType_FloatMana"
	"ActionType_Activate_Mana"
}

set player  0
set turn_no 0
set phase   0
set step    0
set print_phase 1

# foreach line
parse::processFile $fname {PlayerInventory.GetPlayerCards} l {
		# inventory code is in arena.tcl for now
	} {ClientToMatchServiceMessageType_ClientToGREMessage} l {
		set msg [json::json2dict $l]
		set type [dict get $msg "payload" "type"]
		if {$type in $ignore_msgs} {
			continue
		}
		if {$type ne "ClientMessageType_PerformActionResp"} {
			puts "Unknown GRE Message '$type'"
			continue
		}
		set actions [dict get $msg "payload" "performActionResp" "actions"]
		foreach a $actions {
			set at [dict get $a "actionType"]
			if {$at in $ignore_actions} {
				continue
			}
			if {$at eq "ActionType_Play"} {
			} elseif {$at eq "ActionType_CastLeft"} {
			} elseif {$at eq "ActionType_Cast"} {
			} elseif {$at eq "ActionType_Activate"} {
			} elseif {$at eq "ActionType_CastAdventure"} {
			} elseif {$at eq "ActionType_PlayMDFC"} {
			} else {
				puts "Unknown action type in '$a'"
				continue
			}
		}
	} {GreToClientEvent} l {
		set oe [json::json2dict $l]
		set event [dict get $oe "greToClientEvent"]
		set events [dict get $event "greToClientMessages"]
		foreach e $events {
			set type [dict get $e "type"]
			if {$type eq "GREMessageType_DieRollResultsResp"} {
				$::logger dieRolls [dict get $e "dieRollResultsResp" "playerDieRolls"]
			} elseif {$type eq "GREMessageType_ConnectResp"} {
				$::logger startDeck [dict get $e connectResp deckMessage deckCards]
			} elseif {$type eq "GREMessageType_GameStateMessage" ||
			    $type eq "GREMessageType_QueuedGameStateMessage"} {
				set msg [dict get $e "gameStateMessage"]

				set game_info [dGet $e "gameInfo"]
				set game_stage [dGet $game_info "stage"]
				if {$game_stage eq "GameStage_GameOver"} {
					set results [dict get $game_stage "results"]
					set winner [dict get $msg "winningTeamId"]
					set reason [dict get $results "reason"]
					$::logger gameOver $winner $reason

					continue
				}

				set players [dGet $msg "players"]
				foreach p $players {
					set seat [dict get $p "systemSeatNumber"]
					if {[dict exists $p "lifeTotal"]} {
						set life [dict get $p "lifeTotal"]
						dict set p_life $seat $life
					}
				}

				set game_obj [dGet $msg "gameObjects"]
				foreach go $game_obj {
					set instance [dict get $go "instanceId"]
					set card_id  [dict get $go "grpId"]
					dict set game_objs $instance card_id $card_id
				}

				set turn_info [dGet $msg "turnInfo"]
				if {[dict exists $turn_info "activePlayer"]} {
					set p  [dict get $turn_info "activePlayer"]
					if {$p != $player} {
						set player $p
						set print_phase 1
					}
				}
				if {[dict exists $turn_info "turnNumber"]} {
					set tturn  [dict get $turn_info "turnNumber"]
					set tphase [dict get $turn_info "phase"]
					set tstep  [dGet $turn_info "step"]

					if {$tturn != $turn_no || $tphase ne $phase || $tstep ne $step} {
						set turn_no $tturn
						set phase   $tphase
						set step    $tstep
						set print_phase 1
					}
				}

				set anno [dGet $msg "annotations"]
				foreach a $anno {
					set type [dict get $a "type"]

					set zone_xfer_i [lsearch $type "AnnotationType_ZoneTransfer"]
					if {$zone_xfer_i != -1} {
						set details [dict get $a "details"]
						foreach d $details {
							if {[dict get $d "key"] eq "category"} {
								set action [dict get $d "valueString"]
								set verb ""

								if {$action eq "PlayLand"} {
									set verb "Plays"
								} elseif {$action eq "CastSpell"} {
									set verb "Casts"
								} elseif {$action eq "Discard"} {
									set verb "Discards"
								}

								if {$verb ne ""} {
									if {$print_phase} {
										$::logger setPhase $player $turn_no $phase $step
										set print_phase 0
									}
									set aff_ids [dict get $a "affectedIds"]
									if {[llength $aff_ids] != 1} {
										puts "Bad affectedIds in '$e'"
									}
									set instance [lindex $aff_ids 0]
									set card_id [dict get $game_objs $instance card_id]
									set name_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$card_id}]
									$::logger addLine $verb [parse::lookupLocDb ::db $name_id] $card_id
								}
							}
						}
					}

					set dam_anno_i [lsearch $type "AnnotationType_DamageDealt"]
					if {$dam_anno_i != -1} {
						if {$print_phase} {
							$::logger setPhase $player $turn_no $phase $step
							set print_phase 0
						}
						set instance [dict get $a "affectorId"]
						set tgt [lindex [dict get $a "affectedIds"] 0]

						set details [dict get $a "details"]
						set damage ""
						foreach d $details {
							if {[dict get $d "key"] eq "damage"} {
								set damage [dict get $d "valueInt32"]
							}
						}

						set card_id [dict get $game_objs $instance card_id]
						set name_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$card_id}]
						set card_name [parse::lookupLocDb ::db $name_id]

						if {[dict exists $p_life $tgt]} {
							set l [dict get $p_life $tgt]
							$::logger hitPlayer $card_name $tgt $damage $l
						} else {
							set target_id [dict get $game_objs $tgt card_id]
							set tname_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$target_id}]
							set tcard_name [parse::lookupLocDb ::db $tname_id]
							$::logger hitCard $card_name $tcard_name $damage
						}
					}
				}

			} elseif {$type eq "GREMessageType_IntermissionReq"} {
				set msg [dict get $e "intermissionReq"]
				set winner [dict get $msg "winningTeamId"]
				set reason [dict get $msg "result" "reason"]
				$::logger gameOver $winner $reason $p_life
			}
		}
	} {MatchGameRoomStateChangedEvent} l {
		set oe [json::json2dict $l]
		set game_info [dict get $oe "matchGameRoomStateChangedEvent" "gameRoomInfo"]
		if {[dict get $game_info "stateType"] ne "MatchGameRoomStateType_Playing"} {
			continue
		}
		$::logger startGame [dict get $game_info "gameRoomConfig" "reservedPlayers"]
	}
# end of log parsing

itcl::delete object $::logger

