if {![package vsatisfies [package provide Tcl] 8.2]} {return}
package ifneeded tiff 0.2 [list source [file join $dir tiff.tcl]]
