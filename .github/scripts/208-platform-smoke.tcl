set result [open $env(DS9_SMOKE_RESULT) w]
if {[catch {
    wm withdraw .
    package present Tk
    foreach command {fitsy saotk} {
        if {[llength [info commands $command]] != 1} {
            error "Missing native command: $command"
        }
    }
    saotk
    puts $result "PASS Tcl [info patchlevel], Tk [package present Tk], native fitsy/saotk commands initialized"
} message options]} {
    puts $result "FAIL $message"
    puts $result [dict get $options -errorinfo]
    close $result
    exit 1
}
close $result
exit 0
