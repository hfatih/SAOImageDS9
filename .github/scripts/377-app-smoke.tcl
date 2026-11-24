set result [open $env(DS9_MENU_RESULT) w]
proc menuReport {text} {global result; puts $result $text; flush $result}
set assertions 0
proc checkMenu {value description} {
    global assertions
    if {!$value} {error $description}
    incr assertions
}
proc menuLeaves {m} {
    set leaves {}
    set last [$m index end]
    if {$last eq {none}} {return $leaves}
    for {set ii 0} {$ii <= $last} {incr ii} {
        if {[$m type $ii] eq {cascade}} {
            set leaves [concat $leaves [menuLeaves [$m entrycget $ii -menu]]]
        } elseif {[$m type $ii] ni {separator tearoff}} {lappend leaves [list $m $ii]}
    }
    return $leaves
}
proc menuNamed {m label} {
    foreach entry [menuLeaves $m] {
        lassign $entry widget index
        if {[$widget entrycget $index -label] eq $label} {return $entry}
    }
    error "Missing menu entry $label in $m"
}
menuReport "START Tcl=[info patchlevel] Tk=[package present Tk] wm=[tk windowingsystem]"
if {[catch {
    checkMenu [expr {[tk windowingsystem] eq {aqua}}] {Expected actual Aqua application}
    set ds9(menu,size,wrap) 20
    while {[llength $ds9(frames)] < 23} {ds9Cmd {-frame new}}
    UpdateFrameMenuItems
    checkMenu [winfo exists $ds9(mb).frame.goto.group0] {Actual Goto frame menu was not grouped}
    checkMenu [expr {[llength [menuLeaves $ds9(mb).frame.goto]] == 23}] {Actual frame count changed}
    set lastFrame [lindex $ds9(frames) end]
    set lastLabel "[msgcat::mc {Frame}] [string range $lastFrame 5 end]"
    set active($lastFrame) 0
    UpdateActiveFrames
    lassign [menuNamed $ds9(mb).frame.goto $lastLabel] widget index
    checkMenu [expr {[$widget entrycget $index -state] eq {disabled}}] {Disabled frame state did not reach grouped entry}
    lassign [menuNamed $ds9(mb).frame.active $lastLabel] widget index
    $widget invoke $index
    checkMenu $active($lastFrame) {Actual grouped checkbutton did not reactivate the frame}
    lassign [menuNamed $ds9(mb).frame.goto $lastLabel] widget index
    checkMenu [expr {[$widget entrycget $index -state] eq {normal}}] {Reactivated frame remains disabled}
    $widget invoke $index
    checkMenu [expr {$current(frame) eq $lastFrame}] {Actual Goto callback did not select last frame}
    UpdateFrameMenuItems
    checkMenu [expr {[llength [menuLeaves $ds9(mb).frame.goto]] == 23}] {Repeated actual frame rebuild duplicated entries}
    menuReport {PASS actual DS9 frame grouping, goto callback, checkbox and enabled state}

    set colors $ds9(icons,left).color.m
    checkMenu [winfo exists $colors.group0] {Actual region-color menu was not grouped}
    set firstLabel [$colors entrycget 0 -label]
    checkMenu [expr {$firstLabel ne { - } && $firstLabel ne {}}] {Actual region-color group label is blank}
    lassign [lindex [menuLeaves $colors] end] widget index
    set expectedColor [$widget entrycget $index -label]
    checkMenu [expr {[$widget entrycget $index -image] ne {}}] {Actual region-color image was lost}
    $widget invoke $index
    menuReport "PASS actual region-color callback: $marker(color), group=$firstLabel"

    set view(icons) 1
    UpdateColormapMenuSwatches
    set nestedSwatches 0
    foreach entry [menuLeaves $ds9(mb).color] {
        lassign $entry widget index
        if {[$widget type $index] eq {radiobutton} &&
            [$widget entrycget $index -variable] eq {colorbar(map)} &&
            [string match *.group* $widget] && [$widget entrycget $index -image] ne {}} {
            incr nestedSwatches
        }
    }
    checkMenu [expr {$nestedSwatches > 20}] {Actual nested colormap swatches were not updated}
    set view(icons) 0
    UpdateColormapMenuSwatches
    foreach entry [menuLeaves $ds9(mb).color] {
        lassign $entry widget index
        if {[$widget type $index] eq {radiobutton} &&
            [$widget entrycget $index -variable] eq {colorbar(map)}} {
            checkMenu [expr {[$widget entrycget $index -image] eq {}}] {Actual colormap swatch was not cleared}
        }
    }
    menuReport "PASS actual nested colormap swatches: $nestedSwatches"
    while {[llength $ds9(frames)] > 3} {DeleteFrame [lindex $ds9(frames) end]}
    UpdateFrameMenuItems
    checkMenu [expr {![winfo exists $ds9(mb).frame.goto.group0]}] {Actual short frame menu kept obsolete groups}
    checkMenu [expr {[llength [menuLeaves $ds9(mb).frame.goto]] == 3}] {Actual frame shrink changed entry count}
    menuReport {PASS actual frame deletion and short-menu restoration}
    while {[llength $ds9(frames)] < 23} {ds9Cmd {-frame new}}
    UpdateFrameMenuItems
    menuReport "PASS actual DS9 Aqua: $assertions assertions"
} error options]} {
    menuReport "FAIL $error"
    menuReport [dict get $options -errorinfo]
    close $result
    exit 1
}
if {[info exists env(DS9_MENU_CAPTURE)]} {
    menuReport {READY_FOR_CAPTURE}
    # The external runner captures a native open menu, then terminates this fixture.
    after 500 [list tk_popup $ds9(mb).frame.goto 120 120]
} else {close $result; exit 0}
