if {![package vsatisfies [package provide Tcl] 8.2]} {return}
package ifneeded control 0.1.1 [list source [file join $dir control.tcl]]
