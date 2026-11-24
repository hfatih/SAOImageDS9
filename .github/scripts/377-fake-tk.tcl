# Tcl-only menu double. The same regression script also runs against native Tk.
array set fakeMenus {}
proc menu {name args} {
    global fakeMenus
    set fakeMenus($name) {}
    interp alias {} $name {} FakeMenu $name
    return $name
}
proc winfo {what name} {
    global fakeMenus
    switch $what {
        exists {return [info exists fakeMenus($name)]}
        class {return Menu}
        children {
            set result {}
            foreach child [array names fakeMenus] {
                if {[string range $child 0 [string last . $child]-1] eq $name} {
                    lappend result $child
                }
            }
            return [lsort $result]
        }
    }
}
proc destroy {name} {
    global fakeMenus
    if {![info exists fakeMenus($name)]} {return}
    foreach child [winfo children $name] {destroy $child}
    unset fakeMenus($name)
    if {[llength [info commands ::AquaMenu$name]]} {
        rename ::AquaMenu$name {}
        AquaMenuDestroy $name $name
    } elseif {[llength [info commands $name]]} {
        rename $name {}
    }
}
proc bind {args} {}
proc pack {args} {}
proc FakeIndex {name index} {
    global fakeMenus
    if {$index eq {end}} {return [expr {[llength $fakeMenus($name)]-1}]}
    if {[string is integer -strict $index]} {return $index}
    set number 0
    foreach item $fakeMenus($name) {
        if {[dict exists $item -label] && [string match $index [dict get $item -label]]} {return $number}
        incr number
    }
    error "bad menu entry index: $index"
}
proc FakeMenu {name method args} {
    global fakeMenus
    switch -glob $method {
        configure {return}
        add {
            set item [dict create type [lindex $args 0] -label {} -command {} \
                -state normal -columnbreak 0 -image {} -compound none]
            foreach {key value} [lrange $args 1 end] {dict set item $key $value}
            lappend fakeMenus($name) $item
        }
        index {
            set index [FakeIndex $name [lindex $args 0]]
            if {$index < 0} {
                global ds9
                if {$ds9(wm) eq {aqua}} {return {}}
                return none
            }
            return $index
        }
        type {return [dict get [lindex $fakeMenus($name) [FakeIndex $name [lindex $args 0]]] type]}
        entrycget {
            return [dict get [lindex $fakeMenus($name) [FakeIndex $name [lindex $args 0]]] [lindex $args 1]]
        }
        entryconf* {
            set index [FakeIndex $name [lindex $args 0]]
            set item [lindex $fakeMenus($name) $index]
            if {[llength $args] == 1} {
                set options {}
                dict for {key value} $item {
                    if {$key ne {type}} {lappend options [list $key {} {} {} $value]}
                }
                return $options
            }
            foreach {key value} [lrange $args 1 end] {dict set item $key $value}
            lset fakeMenus($name) $index $item
        }
        delete {
            set first [FakeIndex $name [lindex $args 0]]
            set last $first
            if {[llength $args] > 1} {set last [FakeIndex $name [lindex $args 1]]}
            set fakeMenus($name) [lreplace $fakeMenus($name) $first $last]
        }
        invoke {
            set item [lindex $fakeMenus($name) [FakeIndex $name [lindex $args 0]]]
            if {[dict get $item -state] eq {disabled}} {return}
            switch [dict get $item type] {
                radiobutton {uplevel #0 [list set [dict get $item -variable] [dict get $item -value]]}
                checkbutton {
                    set var [dict get $item -variable]
                    if {[uplevel #0 [list info exists $var]] && [uplevel #0 [list set $var]]} {
                        uplevel #0 [list set $var 0]
                    } else {uplevel #0 [list set $var 1]}
                }
            }
            set command [dict get $item -command]
            if {$command ne {}} {return [uplevel #0 $command]}
        }
        default {error "Unsupported menu method $method"}
    }
}
