#!/usr/bin/env tclsh
lappend ::auto_path [file dirname $argv0]
package require json
package require sqlite3
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

### helper functions
proc dGet {d k} {
	if {[dict exists $d $k]} {
		return [dict get $d $k]
	}
	return ""
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

### parse log
set f [open $fname]

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
	} elseif {[regexp {ClientToMatchServiceMessageType_ClientToGREMessage} $hdr]} {
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
			} else {
				puts "Unknown action type in '$a'"
				continue
			}
		}
	} elseif {[regexp {GreToClientEvent} $hdr]} {
		set event [json::json2dict $l]
		set event [dict get $event "greToClientEvent"]
		set events [dict get $event "greToClientMessages"]
		foreach e $events {
			set type [dict get $e "type"]
			if {$type eq "GREMessageType_DieRollResultsResp"} {
				set rolls [dict get $e "dieRollResultsResp" "playerDieRolls"]
				set txt ""
				foreach r $rolls {
					append txt " seat [dict get $r "systemSeatId"]"
					append txt " roll [dict get $r "rollValue"]"
				}
				puts "\nStart game:$txt"
			} elseif {$type eq "GREMessageType_GameStateMessage"} {
				set msg [dict get $e "gameStateMessage"]

				set game_info [dGet $e "gameInfo"]
				set game_stage [dGet $game_info "stage"]
				if {$game_stage eq "GameStage_GameOver"} {
					set results [dict get $game_stage "results"]
					set winner [dict get $msg "winningTeamId"]
					set reason [dict get $results "reason"]

					if {$reason eq "ResultReason_Game"} {
						puts "Game over: Player $winner wins"
					} elseif {$reason eq "ResultReason_Concede"} {
						puts "Game over: Player $winner wins (other player concedes)"
					} else {
						puts "Game over: Player $winner wins, $reason"
					}
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
								}

								if {$verb ne ""} {
									if {$print_phase} {
										if {$step ne ""} {
											puts "Player $player, turn $turn_no, $phase, $step"
										} else {
											puts "Player $player, turn $turn_no, $phase"
										}
										set print_phase 0
									}
									set aff_ids [dict get $a "affectedIds"]
									if {[llength $aff_ids] != 1} {
										puts "Bad affectedIds in '$e'"
									}
									set instance [lindex $aff_ids 0]
									set card_id [dict get $game_objs $instance card_id]
									set name_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$card_id}]
									puts "   $verb [parse::lookupLocDb ::db $name_id]"
								}
							}
						}
					}

					set dam_anno_i [lsearch $type "AnnotationType_DamageDealt"]
					if {$dam_anno_i != -1} {
						if {$print_phase} {
							puts "Player $player, turn $turn_no, $phase, $step"
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
						puts -nonewline "   $card_name hits "
						if {[dict exists $p_life $tgt]} {
							set l [dict get $p_life $tgt]
							puts "player $tgt for $damage, life is $l"
						} else {
							set target_id [dict get $game_objs $tgt card_id]
							set tname_id [::db onecolumn {SELECT name_id FROM cards WHERE card_id=$target_id}]
							set tcard_name [parse::lookupLocDb ::db $tname_id]
							puts "$tcard_name for $damage"
						}
					}
				}

			} elseif {$type eq "GREMessageType_IntermissionReq"} {
				set msg [dict get $e "intermissionReq"]
				set winner [dict get $msg "winningTeamId"]
				set reason [dict get $msg "result" "reason"]

				if {$reason eq "ResultReason_Game"} {
					puts "Game over: Player $winner wins"
				} elseif {$reason eq "ResultReason_Concede"} {
					puts "Game over: Player $winner wins (other player concedes)"
				} else {
					puts "Game over: Player $winner wins, $reason"
				}
				puts "Life totals: $p_life"
			}
		}
	} else {
		#puts "$hdr $l"
	}
}
# end of log parsing

