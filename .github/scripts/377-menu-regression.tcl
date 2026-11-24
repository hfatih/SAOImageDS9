package require msgcat
if {[info exists env(DS9_FAKE_TK)]} {
    source [file join [file dirname [info script]] 377-fake-tk.tcl]
    set ds9(wm) aqua
    if {[info exists env(DS9_TEST_WM)]} {set ds9(wm) $env(DS9_TEST_WM)}
} else {
    package require Tk
    set ds9(wm) [tk windowingsystem]
    wm withdraw .
}
set root [lindex $argv 0]
foreach file {menu bin cat catplot colorbar icons iconsleft mcolor mframe prism table starbase} {
    source [file join $root ds9 library $file.tcl]
}
proc ThemeConfigMenu {w} {}
set ds9(menu,size,wrap) 20
set passed 0
proc equal {actual expected label} {
    global passed
    if {$actual ne $expected} {error "$label: expected <$expected>, got <$actual>"}
    incr passed
}
proc leafEntries {menu} {
    set result {}
    set last [$menu index end]
    if {$last eq {none}} {return $result}
    for {set ii 0} {$ii <= $last} {incr ii} {
        if {[$menu type $ii] eq {cascade}} {
            set result [concat $result [leafEntries [$menu entrycget $ii -menu]]]
        } else {lappend result [list $menu $ii]}
    }
    return $result
}
proc labels {menu} {
    set result {}
    foreach entry [leafEntries $menu] {
        lassign $entry widget index
        if {[$widget type $index] ni {separator tearoff}} {
            lappend result [$widget entrycget $index -label]
        }
    }
    return $result
}
proc newMenu {name} {ThemeMenu $name; $name configure -tearoff 0}
proc columns {count} {
    set result {}
    for {set ii 1} {$ii <= $count} {incr ii} {lappend result col$ii}
    return $result
}
set names [columns 45]
menu .bin
BinPopUp dbin(xcol) .bin $names {set ::binChanged 1}
if {$ds9(wm) eq {aqua}} {
    # Baseline fails here: all 45 entries remain at the native root menu.
    equal [.bin index end] 2 {Aqua long-list root has three groups}
    equal [.bin type 0] cascade {Aqua entries are native cascades}
} else {
    equal [.bin index end] 44 {Non-Aqua list stays flat}
    equal [.bin entrycget 20 -columnbreak] 1 {Existing column break retained}
}
equal [labels .bin] $names {All bin columns retained in original order}
lassign [lindex [leafEntries .bin] end] widget index
$widget invoke $index
equal $dbin(xcol) col45 {Last bin column selected}
equal $binChanged 1 {Original callback ran}
destroy .bin

foreach count {0 1 20 21 40 41} {
    newMenu .sizes
    foreach label [columns $count] {.sizes add command -label $label -command [list set ::picked $label]}
    AquaMenuGroup .sizes
    equal [labels .sizes] [columns $count] "Boundary $count preserves contents"
    if {$ds9(wm) eq {aqua} && $count > 20} {
        equal [.sizes index end] [expr {($count-1)/20}] "Boundary $count group count"
    }
    AquaMenuUngroup .sizes
    equal [labels .sizes] [columns $count] "Boundary $count flatten"
    equal [winfo children .sizes] {} "Boundary $count cleans submenu widgets"
    destroy .sizes
}

newMenu .properties
.properties add command -label {Show All} -command {set ::fixed 1}
.properties add command -label {Hide All} -command {set ::fixed 0}
.properties add separator
set selected col41
foreach label [columns 41] {
    .properties add radiobutton -label $label -variable selected -value $label \
        -command [list set ::picked $label]
}
set before [labels .properties]
AquaMenuGroup .properties 3
equal [.properties entrycget 0 -label] {Show All} {Fixed root item retained}
equal [.properties type 2] separator {Fixed separator retained}
MenuEntryConfigure .properties col41 -state disabled
lassign [lindex [leafEntries .properties] end] widget index
equal [$widget entrycget $index -state] disabled {Grouped entry state updated}
$widget invoke $index
MenuEntryConfigure .properties col41 -state normal
$widget invoke $index
equal $selected col41 {Radio selection preserved}
equal $picked col41 {Grouped callback preserved}
equal [$widget entrycget $index -variable] selected {Variable preserved}
AquaMenuUngroup .properties 3
equal [labels .properties] $before {Flatten preserves prefix and leaves}
equal [winfo children .properties] {} {Flatten removes obsolete groups}
.properties delete 3 end
.properties add checkbutton -label single -variable checked -command {set ::toggled 1}
AquaMenuGroup .properties 3
equal [.properties type 3] checkbutton {Shrinking list becomes flat}
.properties invoke 3
equal $checked 1 {Checkbutton state preserved}
equal $toggled 1 {Checkbutton callback preserved}
destroy .properties
set ds9(mb) .frames
set ds9(menu,size,frame,goto) 0
set ds9(menu,size,frame,active) 3
set debug(tcl,update) 0
foreach m {.frames .frames.frame .frames.frame.goto .frames.frame.active} {newMenu $m}
.frames.frame.active add command -label {Show All}
.frames.frame.active add command -label {Hide All}
.frames.frame.active add separator
set ds9(frames) {}
for {set ii 1} {$ii <= 45} {incr ii} {lappend ds9(frames) Frame$ii}
UpdateFrameMenuItems
equal [llength [labels .frames.frame.goto]] 45 {Real frame builder retains all frames}
equal [llength [labels .frames.frame.active]] 47 {Real active-frame builder retains fixed items}
UpdateFrameMenuItems
equal [llength [labels .frames.frame.goto]] 45 {Repeated frame rebuild is idempotent}
set ds9(frames) {Frame1 Frame2 Frame3}
UpdateFrameMenuItems
equal [.frames.frame.goto index end] 2 {Real frame list shrinks back to flat}
equal [.frames.frame.active entrycget 0 -label] {Show All} {Real frame prefix survives rebuild}
equal [winfo children .frames.frame.goto] {} {Old frame submenus destroyed}
destroy .frames

# Real Starbase data and real list builders; only unrelated application callbacks are replaced.
set names [columns 45]
starbase_new testdb {*}$names
array set catalog {catdb testdb tbldb testdb ramenu .ra decmenu .dec sortmenu .sort}
foreach m {.ra .dec .sort .plot .hist .prism} {newMenu $m}
CATColsMenu catalog
equal [labels .ra.menu] $names {RA column builder retains contents}
equal [labels .dec.menu] $names {Dec column builder retains contents}
CATPlotDialogColsMenu catalog .plot x
CATHistogramColsMenu catalog .hist x {}
PrismColsMenu catalog .prism x {}
TBLSortMenu catalog
equal [labels .plot.menu] $names {Plot column builder retains contents}
equal [labels .hist.menu] $names {Histogram column builder retains contents}
equal [labels .prism.menu] [linsert $names 0 {}] {Prism blank choice retained}
equal [labels .sort.menu] [linsert $names 0 {}] {Sort blank choice retained}
lassign [lindex [leafEntries .hist.menu] end] widget index
$widget invoke $index
equal $ed3(x) col45 {Histogram last-entry callback updates its original variable}
foreach m {.ra .dec .sort .plot .hist .prism} {destroy $m}

if {[info exists env(DS9_FAKE_TK)]} {
    namespace eval ttk {}
    proc ttk::menubutton {name args} {menu $name}
    set fakeImage 0
    proc image {args} {global fakeImage; return image[incr fakeImage]}
    menu .iconcase
} else {ttk::frame .iconcase}
namespace eval tooltip {}
proc tooltip::tooltip {args} {}
set ds9(icons,left) .iconcase
set ds9(icons,colors) [file join $root ds9 icons colors]
set marker(color) red
CreateIconsLeftMarkerColor
if {$ds9(wm) eq {aqua}} {
    set seen {}
    for {set ii 0} {$ii <= [.iconcase.color.m index end]} {incr ii} {
        set label [.iconcase.color.m entrycget $ii -label]
        if {$label eq { - } || $label eq {}} {error {Region-color groups need meaningful labels}}
        lappend seen $label
    }
    equal [llength [lsort -unique $seen]] [llength $seen] {Color group captions distinguish ranges}
}
trace remove variable marker(color) write [list IconMenuButtonCB .iconcase.color]
destroy .iconcase

newMenu .swatches
newMenu .swatches.color
if {[info exists env(DS9_FAKE_TK)]} {set testSwatch sampleImage} else {set testSwatch [image create photo -width 2 -height 2]}
proc ColormapSwatch {name} {global testSwatch; return $testSwatch}
set icolorbar(test,cmaps) [columns 45]
set ds9(mb) .swatches
ColorMainMenuExternal test
.swatches.color add cascade -label Map -menu .swatches.color.test
newMenu .dialog
newMenu .dialog.colormap
set icolorbar(mb) .dialog
ColormapDialogExternal test
.dialog.colormap add cascade -label Map -menu .dialog.colormap.test
set view(icons) 1
UpdateColormapMenuSwatches
foreach rootMenu {.swatches.color.test .dialog.colormap.test} {
    equal [labels $rootMenu] [columns 45] {Colormap builder preserves all maps}
    foreach entry [leafEntries $rootMenu] {
        lassign $entry widget index
        equal [$widget entrycget $index -image] $testSwatch {Nested colormap swatch enabled}
    }
}
set view(icons) 0
UpdateColormapMenuSwatches
foreach entry [leafEntries .swatches.color.test] {
    lassign $entry widget index
    equal [$widget entrycget $index -image] {} {Nested colormap swatch cleared}
}
destroy .swatches
destroy .dialog
newMenu .properties
equal [.properties index end] none {Destroy and recreate is clean}
destroy .properties
puts "PASS $passed assertions on $ds9(wm)"
if {![info exists env(DS9_FAKE_TK)]} {exit 0}
