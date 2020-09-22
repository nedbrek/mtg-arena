Requires Tcl JSON parser (tcllib)
and libsqlite3-tcl

The configuration files are named `data_loc_${SHA}.mtga` and `data_cards_${SHA}.mtga` 

To run:
`tclsh config.tcl $loc $cards`

Or:
```
tclsh makeCardDb.tcl
./arena.tcl <logfile>
./checklist.tcl
```

