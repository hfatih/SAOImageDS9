# Capability probe only: no DS9 menu layout changes.
package require Tk
set output [open $env(AQUA_PROBE_RESULT) w]
proc report {text} {
    global output
    puts $output $text
    flush $output
}
if {[catch {
    set system [tk windowingsystem]
    report "Tcl=[info patchlevel] Tk=[package present Tk] windowingsystem=$system"
    if {$system ne {aqua}} {error "Expected native Aqua, got $system"}
    wm title . {DS9 issue 377 Aqua capability probe}
    wm geometry . 640x240+100+100
    label .heading -text {Native Aqua / bundled Tcl-Tk 9.0.4} -font {Helvetica 18}
    label .detail -text {Menu construction, selection, and callbacks are checked below.}
    pack .heading .detail -pady 20
    menu .bar -tearoff 0
    . configure -menu .bar
    menu .bar.long -tearoff 0
    .bar add cascade -label {Long menu} -menu .bar.long
    set selected {}
    for {set index 0} {$index < 80} {incr index} {
        .bar.long add radiobutton -label "Entry $index" \
            -variable selected -value $index -command [list set callback $index]
    }
    .bar.long entryconfigure 40 -columnbreak 1
    if {[.bar.long index end] != 79} {error {Unexpected long-menu entry count}}
    .bar.long invoke 79
    if {$selected != 79 || $callback != 79} {error {Long-menu callback failed}}
    report {PASS long menu: all 80 entries retained; last selection and callback work}
    report "columnbreak option accepted=[.bar.long entrycget 40 -columnbreak]; visual column layout not asserted"
    menu .bar.grouped -tearoff 0
    .bar add cascade -label {Grouped alternative} -menu .bar.grouped
    for {set group 0} {$group < 4} {incr group} {
        set submenu .bar.grouped.g$group
        menu $submenu -tearoff 0
        set first [expr {$group*20}]
        set last [expr {$first+19}]
        .bar.grouped add cascade -label "$first-$last" -menu $submenu
        for {set index $first} {$index <= $last} {incr index} {
            $submenu add radiobutton -label "Entry $index" \
                -variable selected -value $index -command [list set callback $index]
        }
    }
    .bar.grouped.g3 invoke 19
    if {$selected != 79 || $callback != 79} {error {Grouped-menu callback failed}}
    update
    report {PASS grouped menu: four native submenus, selection and callback work}
} message options]} {
    report "FAIL $message"
    report [dict get $options -errorinfo]
    close $output
    exit 1
}
after 2500 {
    # Screenshots may be unavailable on a hosted runner. Record this separately.
    if {[catch {exec /usr/sbin/screencapture -x $env(AQUA_PROBE_SCREENSHOT)} reason]} {
        report "SCREENSHOT_UNAVAILABLE $reason"
    } else {
        report {SCREENSHOT_CAPTURED (unopened menus; no visual column assertion)}
    }
    report {PASS native Aqua execution probe}
    close $output
    exit 0
}
