# md5.tcl - Copyright (C) 2003 Pat Thoyts <patthoyts@users.sourceforge.net>
#
# MD5  defined by RFC 1321, "The MD5 Message-Digest Algorithm"
# HMAC defined by RFC 2104, "Keyed-Hashing for Message Authentication"
#
# -------------------------------------------------------------------------
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
# -------------------------------------------------------------------------
#
# $Id: md5x.tcl,v 1.1.2.1 2003/05/05 17:22:50 patthoyts Exp $

package require Tcl 8.2;                # tcl minimum version
catch {package require md5c 1.0};       # tcllib critcl alternative

namespace eval ::md5 {
    variable version 2.0.0
    variable rcsid {$Id: md5x.tcl,v 1.1.2.1 2003/05/05 17:22:50 patthoyts Exp $}

    namespace export md5 hmac MD5Init MD5Update MD5Final

    variable T
    if {![info exists T]} {
        # RFC 1321:3.4 step 4: construct 
        set T X
        for {set i 1} {$i < 65} {incr i} {
            lappend T [expr {4294967296 * abs(sin($i))}]
        }
        unset i
    }

    variable uid
    if {![info exists uid]} {
        set uid 0
    }
}

# -------------------------------------------------------------------------

# MD5Init - create and initialize an MD5 state variable. This will be
# cleaned up when we call MD5Final
#
proc ::md5::MD5Init {} {
    variable uid
    set token [namespace current]::[incr uid]
    upvar #0 $token tok

    # RFC1321:3.3 - Initialize MD5 state structure
    array set tok \
        [list \
             A [expr 0x67452301] \
             B [expr 0xefcdab89] \
             C [expr 0x98badcfe] \
             D [expr 0x10325476] \
             n 0 i "" ]
    return $token
}

proc ::md5::MD5Update {token data} {
    variable $token
    upvar 0 $token state

    if {[package provide md5c] != {}} {
        if {[info exists state(md5c)]} {
            set state(md5c) [md5c $data $state(md5c)]
        } else {
            set state(md5c) [md5c $data]
        }
        return
    }

    # Update the state values
    incr state(n) [string length $data]
    append state(i) $data

    # Calculate the hash for any complete blocks
    set len [string length $state(i)]
    for {set n 0} {($n + 64) <= $len} {} {
        MD5Hash $token [string range $state(i) $n [incr n 64]]
    }

    # Adjust the state for the blocks completed.
    set state(i) [string range $state(i) $n end]
    return
}

proc ::md5::MD5Final {token} {
    variable $token
    upvar 0 $token state

    if {[package provide md5c] != {}} {
        set r $state(md5c)
        unset state
        return $r
    }

    # RFC1321:3.1 - Padding
    #
    set len [string length $state(i)]
    set pad [expr {56 - ($len % 64)}]
    if {$len % 64 > 56} {
        incr pad 64
    }
    if {$pad == 0} {
        incr pad 64
    }
    append state(i) [binary format a$pad \x80]

    # RFC1321:3.2 - Append length in bits as little-endian wide int.
    append state(i) [binary format ii [expr {8 * $state(n)}] 0]

    # Calculate the hash for the remaining block.
    set len [string length $state(i)]
    for {set n 0} {($n + 64) <= $len} {} {
        MD5Hash $token [string range $state(i) $n [incr n 64]]
    }

    # RFC1321:3.5 - Output
    set r [binary format i4 [list $state(A) $state(B) $state(C) $state(D)]]
    unset state
    return $r
}

# -------------------------------------------------------------------------
# HMAC Hashed Message Authentication (RFC 2104)
#
# hmac = H(K xor opad, H(K xor ipad, text))
#
proc ::md5::HMACInit {K} {

    # Key K is adjusted to be 64 bytes long. If K is larger, then use
    # the MD5 digest of K and pad this instead.
    set len [string length $K]
    if {$len > 64} {
        set tok [MD5Init]
        MD5Update $tok $K
        set K [MD5Final $tok]
        set len [string length $K]
    }
    set pad [expr {64 - $len}]
    append K [string repeat \0 $pad]

    # Cacluate the padding buffers.
    set Ki {}
    set Ko {}
    binary scan $K i16 Ks
    foreach k $Ks {
        append Ki [binary format i [expr {$k ^ 0x36363636}]]
        append Ko [binary format i [expr {$k ^ 0x5c5c5c5c}]]
    }

    set tok [MD5Init]
    MD5Update $tok $Ki;                 # initialize with the inner pad
    
    # preserve the Ko value for the final stage.
    set [subst $tok](Ko) $Ko

    return $tok
}

proc ::md5::HMACUpdate {token data} {
    MD5Update $token $data
    return
}

proc ::md5::HMACFinal {token} {
    variable $token
    upvar 0 $token state

    set tok [MD5Init];                  # init the outer hashing function
    MD5Update $tok $state(Ko);          # prepare with the outer pad.
    MD5Update $tok [MD5Final $token];   # hash the inner result
    return [MD5Final $tok]
}

# -------------------------------------------------------------------------

set ::md5::MD5Hash_body {
    variable $token
    upvar 0 $token state

    # RFC1321:3.4 - Process Message in 16-Word Blocks
    binary scan $msg i* blocks
    foreach {X0 X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12 X13 X14 X15} $blocks {
        set A $state(A)
        set B $state(B)
        set C $state(C)
        set D $state(D)

        # Round 1
        # Let [abcd k s i] denote the operation
        #   a = b + ((a + F(b,c,d) + X[k] + T[i]) <<< s).
        # Do the following 16 operations.
        # [ABCD  0  7  1]  [DABC  1 12  2]  [CDAB  2 17  3]  [BCDA  3 22  4]
        set A [expr {$B + (($A + [F $B $C $D] + $X0 + $T01) <<< 7)}]
        set D [expr {$A + (($D + [F $A $B $C] + $X1 + $T02) <<< 12)}]
        set C [expr {$D + (($C + [F $D $A $B] + $X2 + $T03) <<< 17)}]
        set B [expr {$C + (($B + [F $C $D $A] + $X3 + $T04) <<< 22)}]
        # [ABCD  4  7  5]  [DABC  5 12  6]  [CDAB  6 17  7]  [BCDA  7 22  8]
        set A [expr {$B + (($A + [F $B $C $D] + $X4 + $T05) <<< 7)}]
        set D [expr {$A + (($D + [F $A $B $C] + $X5 + $T06) <<< 12)}]
        set C [expr {$D + (($C + [F $D $A $B] + $X6 + $T07) <<< 17)}]
        set B [expr {$C + (($B + [F $C $D $A] + $X7 + $T08) <<< 22)}]
        # [ABCD  8  7  9]  [DABC  9 12 10]  [CDAB 10 17 11]  [BCDA 11 22 12]
        set A [expr {$B + (($A + [F $B $C $D] + $X8 + $T09) <<< 7)}]
        set D [expr {$A + (($D + [F $A $B $C] + $X9 + $T10) <<< 12)}]
        set C [expr {$D + (($C + [F $D $A $B] + $X10 + $T11) <<< 17)}]
        set B [expr {$C + (($B + [F $C $D $A] + $X11 + $T12) <<< 22)}]
        # [ABCD 12  7 13]  [DABC 13 12 14]  [CDAB 14 17 15]  [BCDA 15 22 16]
        set A [expr {$B + (($A + [F $B $C $D] + $X12 + $T13) <<< 7)}]
        set D [expr {$A + (($D + [F $A $B $C] + $X13 + $T14) <<< 12)}]
        set C [expr {$D + (($C + [F $D $A $B] + $X14 + $T15) <<< 17)}]
        set B [expr {$C + (($B + [F $C $D $A] + $X15 + $T16) <<< 22)}]

        # Round 2.
        # Let [abcd k s i] denote the operation
        #   a = b + ((a + G(b,c,d) + X[k] + Ti) <<< s)
        # Do the following 16 operations.
        # [ABCD  1  5 17]  [DABC  6  9 18]  [CDAB 11 14 19]  [BCDA  0 20 20]
        set A [expr {$B + (($A + [G $B $C $D] + $X1  + $T17) <<<  5)}]
        set D [expr {$A + (($D + [G $A $B $C] + $X6  + $T18) <<<  9)}]
        set C [expr {$D + (($C + [G $D $A $B] + $X11 + $T19) <<< 14)}]
        set B [expr {$C + (($B + [G $C $D $A] + $X0  + $T20) <<< 20)}]
        # [ABCD  5  5 21]  [DABC 10  9 22]  [CDAB 15 14 23]  [BCDA  4 20 24]
        set A [expr {$B + (($A + [G $B $C $D] + $X5  + $T21) <<<  5)}]
        set D [expr {$A + (($D + [G $A $B $C] + $X10 + $T22) <<<  9)}]
        set C [expr {$D + (($C + [G $D $A $B] + $X15 + $T23) <<< 14)}]
        set B [expr {$C + (($B + [G $C $D $A] + $X4  + $T24) <<< 20)}]
        # [ABCD  9  5 25]  [DABC 14  9 26]  [CDAB  3 14 27]  [BCDA  8 20 28]
        set A [expr {$B + (($A + [G $B $C $D] + $X9  + $T25) <<<  5)}]
        set D [expr {$A + (($D + [G $A $B $C] + $X14 + $T26) <<<  9)}]
        set C [expr {$D + (($C + [G $D $A $B] + $X3  + $T27) <<< 14)}]
        set B [expr {$C + (($B + [G $C $D $A] + $X8  + $T28) <<< 20)}]
        # [ABCD 13  5 29]  [DABC  2  9 30]  [CDAB  7 14 31]  [BCDA 12 20 32]
        set A [expr {$B + (($A + [G $B $C $D] + $X13 + $T29) <<<  5)}]
        set D [expr {$A + (($D + [G $A $B $C] + $X2  + $T30) <<<  9)}]
        set C [expr {$D + (($C + [G $D $A $B] + $X7  + $T31) <<< 14)}]
        set B [expr {$C + (($B + [G $C $D $A] + $X12 + $T32) <<< 20)}]
        
        # Round 3.
        # Let [abcd k s i] denote the operation
        #   a = b + ((a + H(b,c,d) + X[k] + T[i]) <<< s)
        # Do the following 16 operations.
        # [ABCD  5  4 33]  [DABC  8 11 34]  [CDAB 11 16 35]  [BCDA 14 23 36]
        set A [expr {$B + (($A + [H $B $C $D] + $X5  + $T33) <<<  4)}]
        set D [expr {$A + (($D + [H $A $B $C] + $X8  + $T34) <<< 11)}]
        set C [expr {$D + (($C + [H $D $A $B] + $X11 + $T35) <<< 16)}]
        set B [expr {$C + (($B + [H $C $D $A] + $X14 + $T36) <<< 23)}]
        # [ABCD  1  4 37]  [DABC  4 11 38]  [CDAB  7 16 39]  [BCDA 10 23 40]
        set A [expr {$B + (($A + [H $B $C $D] + $X1  + $T37) <<<  4)}]
        set D [expr {$A + (($D + [H $A $B $C] + $X4  + $T38) <<< 11)}]
        set C [expr {$D + (($C + [H $D $A $B] + $X7  + $T39) <<< 16)}]
        set B [expr {$C + (($B + [H $C $D $A] + $X10 + $T40) <<< 23)}]
        # [ABCD 13  4 41]  [DABC  0 11 42]  [CDAB  3 16 43]  [BCDA  6 23 44]
        set A [expr {$B + (($A + [H $B $C $D] + $X13 + $T41) <<<  4)}]
        set D [expr {$A + (($D + [H $A $B $C] + $X0  + $T42) <<< 11)}]
        set C [expr {$D + (($C + [H $D $A $B] + $X3  + $T43) <<< 16)}]
        set B [expr {$C + (($B + [H $C $D $A] + $X6  + $T44) <<< 23)}]
        # [ABCD  9  4 45]  [DABC 12 11 46]  [CDAB 15 16 47]  [BCDA  2 23 48]
        set A [expr {$B + (($A + [H $B $C $D] + $X9  + $T45) <<<  4)}]
        set D [expr {$A + (($D + [H $A $B $C] + $X12 + $T46) <<< 11)}]
        set C [expr {$D + (($C + [H $D $A $B] + $X15 + $T47) <<< 16)}]
        set B [expr {$C + (($B + [H $C $D $A] + $X2  + $T48) <<< 23)}]

        # Round 4.
        # Let [abcd k s i] denote the operation
        #   a = b + ((a + I(b,c,d) + X[k] + T[i]) <<< s)
        # Do the following 16 operations.
        # [ABCD  0  6 49]  [DABC  7 10 50]  [CDAB 14 15 51]  [BCDA  5 21 52]
        set A [expr {$B + (($A + [I $B $C $D] + $X0  + $T49) <<<  6)}]
        set D [expr {$A + (($D + [I $A $B $C] + $X7  + $T50) <<< 10)}]
        set C [expr {$D + (($C + [I $D $A $B] + $X14 + $T51) <<< 15)}]
        set B [expr {$C + (($B + [I $C $D $A] + $X5  + $T52) <<< 21)}]
        # [ABCD 12  6 53]  [DABC  3 10 54]  [CDAB 10 15 55]  [BCDA  1 21 56]
        set A [expr {$B + (($A + [I $B $C $D] + $X12 + $T53) <<<  6)}]
        set D [expr {$A + (($D + [I $A $B $C] + $X3  + $T54) <<< 10)}]
        set C [expr {$D + (($C + [I $D $A $B] + $X10 + $T55) <<< 15)}]
        set B [expr {$C + (($B + [I $C $D $A] + $X1  + $T56) <<< 21)}]
        # [ABCD  8  6 57]  [DABC 15 10 58]  [CDAB  6 15 59]  [BCDA 13 21 60]
        set A [expr {$B + (($A + [I $B $C $D] + $X8  + $T57) <<<  6)}]
        set D [expr {$A + (($D + [I $A $B $C] + $X15 + $T58) <<< 10)}]
        set C [expr {$D + (($C + [I $D $A $B] + $X6  + $T59) <<< 15)}]
        set B [expr {$C + (($B + [I $C $D $A] + $X13 + $T60) <<< 21)}]
        # [ABCD  4  6 61]  [DABC 11 10 62]  [CDAB  2 15 63]  [BCDA  9 21 64]
        set A [expr {$B + (($A + [I $B $C $D] + $X4  + $T61) <<<  6)}]
        set D [expr {$A + (($D + [I $A $B $C] + $X11 + $T62) <<< 10)}]
        set C [expr {$D + (($C + [I $D $A $B] + $X2  + $T63) <<< 15)}]
        set B [expr {$C + (($B + [I $C $D $A] + $X9  + $T64) <<< 21)}]

        # Then perform the following additions. (That is, increment each
        # of the four registers by the value it had before this block
        # was started.)
        set state(A) [expr {($A + $state(A)) & 0xFFFFFFFF}]
        set state(B) [expr {($B + $state(B)) & 0xFFFFFFFF}]
        set state(C) [expr {($C + $state(C)) & 0xFFFFFFFF}]
        set state(D) [expr {($D + $state(D)) & 0xFFFFFFFF}]
    }

    return
}

# 32bit rotate-left
proc ::md5::<<< {v n} {
    set v [expr {(($v << $n) | (($v >> (32 - $n)) & (0x7FFFFFFF >> (31 - $n))))}]
    return [expr {$v & 0xFFFFFFFF}]
}

# Convert our <<< pseuodo-operator into a procedure call.
regsub -all -line \
    {\[expr {(\$[ABCD]) \+ \(\((.*)\)\s+<<<\s+(\d+)\)}\]} \
    $::md5::MD5Hash_body \
    {[expr {\1 + [<<< [expr {\2}] \3]}]} \
    ::md5::MD5Hash_bodyX

# RFC1321:3.4 - function F
proc ::md5::F {X Y Z} {
    return [expr {($X & $Y) | ((~$X) & $Z)}]
}

# Inline the F function
regsub -all -line \
    {\[F (\$[ABCD]) (\$[ABCD]) (\$[ABCD])\]} \
    $::md5::MD5Hash_bodyX \
    {( (\1 \& \2) | ((~\1) \& \3) )} \
    ::md5::MD5Hash_bodyX
    
# RFC1321:3.4 - function G
proc ::md5::G {X Y Z} {
    return [expr {(($X & $Z) | ($Y & (~$Z)))}]
}

# Inline the G function
regsub -all -line \
    {\[G (\$[ABCD]) (\$[ABCD]) (\$[ABCD])\]} \
    $::md5::MD5Hash_bodyX \
    {(((\1 \& \3) | (\2 \& (~\3))))} \
    ::md5::MD5Hash_bodyX

# RFC1321:3.4 - function H
proc ::md5::H {X Y Z} {
    return [expr {$X ^ $Y ^ $Z}]
}

# Inline the H function
regsub -all -line \
    {\[H (\$[ABCD]) (\$[ABCD]) (\$[ABCD])\]} \
    $::md5::MD5Hash_bodyX \
    {(\1 ^ \2 ^ \3)} \
    ::md5::MD5Hash_bodyX

# RFC1321:3.4 - function I
proc ::md5::I {X Y Z} {
    return [expr {$Y ^ ($X | (~$Z))}]
}

# Inline the I function
regsub -all -line \
    {\[I (\$[ABCD]) (\$[ABCD]) (\$[ABCD])\]} \
    $::md5::MD5Hash_bodyX \
    {(\2 ^ (\1 | (~\3)))} \
    ::md5::MD5Hash_bodyX


# inline the values of T
namespace eval md5 {
    foreach tName {
        T01 T02 T03 T04 T05 T06 T07 T08 T09 T10 
        T11 T12 T13 T14 T15 T16 T17 T18 T19 T20 
        T21 T22 T23 T24 T25 T26 T27 T28 T29 T30 
        T31 T32 T33 T34 T35 T36 T37 T38 T39 T40 
        T41 T42 T43 T44 T45 T46 T47 T48 T49 T50 
        T51 T52 T53 T54 T55 T56 T57 T58 T59 T60 
        T61 T62 T63 T64 
    }  tVal {
        0xd76aa478 0xe8c7b756 0x242070db 0xc1bdceee
        0xf57c0faf 0x4787c62a 0xa8304613 0xfd469501
        0x698098d8 0x8b44f7af 0xffff5bb1 0x895cd7be
        0x6b901122 0xfd987193 0xa679438e 0x49b40821
        
        0xf61e2562 0xc040b340 0x265e5a51 0xe9b6c7aa
        0xd62f105d 0x2441453  0xd8a1e681 0xe7d3fbc8
        0x21e1cde6 0xc33707d6 0xf4d50d87 0x455a14ed
        0xa9e3e905 0xfcefa3f8 0x676f02d9 0x8d2a4c8a
        
        0xfffa3942 0x8771f681 0x6d9d6122 0xfde5380c
        0xa4beea44 0x4bdecfa9 0xf6bb4b60 0xbebfbc70
        0x289b7ec6 0xeaa127fa 0xd4ef3085 0x4881d05
        0xd9d4d039 0xe6db99e5 0x1fa27cf8 0xc4ac5665
        
        0xf4292244 0x432aff97 0xab9423a7 0xfc93a039
        0x655b59c3 0x8f0ccc92 0xffeff47d 0x85845dd1
        0x6fa87e4f 0xfe2ce6e0 0xa3014314 0x4e0811a1
        0xf7537e82 0xbd3af235 0x2ad7d2bb 0xeb86d391
    } {
        lappend map \$$tName $tVal
    }
    set ::md5::MD5Hash_bodyX [string map $map $::md5::MD5Hash_bodyX]
    unset map
}

# Define the MD5 hashing procedure with inline functions.
proc ::md5::MD5Hash {token msg} $::md5::MD5Hash_bodyX

# -------------------------------------------------------------------------

if {[package provide Trf] != {}} {
    interp alias {} ::md5::Hex {} ::hex -mode encode
} else {
    proc ::md5::Hex {data} {
        set result {}
        binary scan $data c* r
        foreach c $r {
            append result [format "%02X" [expr {$c & 0xff}]]
        }
        return $result
    }
}

# -------------------------------------------------------------------------

# Description:
#  Pop the nth element off a list. Used in options processing.
#
proc ::md5::Pop {varname {nth 0}} {
    upvar $varname args
    set r [lindex $args $nth]
    set args [lreplace $args $nth $nth]
    return $r
}

# -------------------------------------------------------------------------

# fileevent handler for chunked file hashing.
#
proc ::md5::Chunk {token channel {chunksize 4096}} {
    variable $token
    upvar 0 $token state
    
    if {[eof $channel]} {
        fileevent $channel readable {}
        set state(reading) 0
    }
        
    MD5Update $token [read $channel $chunksize]
}

# -------------------------------------------------------------------------

proc ::md5::md5 {args} {
    array set opts {-hex 0 -filename {} -channel {} -chunksize 4096}
    while {[string match -* [set option [lindex $args 0]]]} {
        switch -glob -- $option {
            -hex       { set opts(-hex) 1 }
            -file*     { set opts(-filename) [Pop args 1] }
            -channel   { set opts(-channel) [Pop args 1] }
            -chunksize { set opts(-chunksize) [Pop args 1] }
            --         { Pop args ; break }
            default {
                set err [join [lsort [array names opts]] ", "]
                return -code error "bad option $option:\
                    must be one of $err"
            }
        }
        Pop args
    }

    if {$opts(-filename) != {}} {
        set opts(-channel) [open $opts(-filename) r]
        fconfigure $opts(-channel) -translation binary
    }

    if {$opts(-channel) == {}} {

        if {[llength $args] != 1} {
            return -code error "wrong # args:\
                should be \"md5 ?-hex? -filename file | string\""
        }
        set tok [MD5Init]
        MD5Update $tok [lindex $args 0]
        set r [MD5Final $tok]

    } else {

        set tok [MD5Init]
        set [subst $tok](reading) 1
        fileevent $opts(-channel) readable \
            [list [namespace origin Chunk] \
                 $tok $opts(-channel) $opts(-chunksize)]
        vwait [subst $tok](reading)
        set r [MD5Final $tok]

        # If we opened the channel - we should close it too.
        if {$opts(-filename) != {}} {
            close $opts(-channel)
        }
    }
    
    if {$opts(-hex)} {
        set r [Hex $r]
    }
    return $r
}

# -------------------------------------------------------------------------

proc ::md5::hmac {args} {
    array set opts {-hex 0 -filename {} -channel {} -chunksize 4096 -key {}}
    while {[string match -* [set option [lindex $args 0]]]} {
        switch -glob -- $option {
            -key       { set opts(-key) [Pop args 1] }
            -hex       { set opts(-hex) 1 }
            -file*     { set opts(-filename) [Pop args 1] }
            -channel   { set opts(-channel) [Pop args 1] }
            -chunksize { set opts(-chunksize) [Pop args 1] }
            --         { Pop args ; break }
            default {
                set err [join [lsort [array names opts]] ", "]
                return -code error "bad option $option:\
                    must be one of $err"
            }
        }
        Pop args
    }

    if {$opts(-key) == {}} {
        return -code error "wrong # args:\
            should be \"hmac ?-hex? -key key -filename file | string\""
    }

    if {$opts(-filename) != {}} {
        set opts(-channel) [open $opts(-filename) r]
        fconfigure $opts(-channel) -translation binary
    }

    if {$opts(-channel) == {}} {

        if {[llength $args] != 1} {
            return -code error "wrong # args:\
                should be \"hmac ?-hex? -key key -filename file | string\""
        }
        set tok [HMACInit $opts(-key)]
        HMACUpdate $tok [lindex $args 0]
        set r [HMACFinal $tok]

    } else {

        set tok [HMACInit $opts(-key)]
        set [subst $tok](reading) 1
        fileevent $opts(-channel) readable \
            [list [namespace origin Chunk] \
                 $tok $opts(-channel) $opts(-chunksize)]
        vwait [subst $tok](reading)
        set r [HMACFinal $tok]

        # If we opened the channel - we should close it too.
        if {$opts(-filename) != {}} {
            close $opts(-channel)
        }
    }
    
    if {$opts(-hex)} {
        set r [Hex $r]
    }
    return $r
}

# -------------------------------------------------------------------------

package provide md5 $::md5::version

# -------------------------------------------------------------------------
# Local Variables:
#   mode: tcl
#   indent-tabs-mode: nil
# End:


