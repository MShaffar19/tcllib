# -*- tcl -*-
# --------------------------------------------------------------
# List of modules to install and definitions guiding the process of
# doing so.
#
# This file is shared between 'installer.tcl' and 'sak.tcl', like
# 'tcllib_version.tcl'. The swiss army knife requires access to the
# data in this file to be able to check if there are modules in the
# directory hierarchy, but missing in the list of installed modules.
# --------------------------------------------------------------

# Excluded:
#    calendar	 _tci _man  _null

set     modules [list]
array set guide {}
foreach {m pkg doc exa} {
    base64	_tcl  _man  _null
    cmdline	_tcl  _man  _null
    comm	_tcl  _man  _null
    control	 _tci _man  _null
    counter	_tcl  _man  _null
    crc		_tcl  _man  _null
    csv		_tcl  _man _exa
    des		_tcl  _man  _null
    dns		_tcl  _man _exa
    doctools	 _doc _man _exa
    exif	_tcl  _man  _null
    fileutil	_tcl  _man  _null
    ftp		_tcl  _man _exa
    ftpd	_tcl  _man _exa
    html	_tcl  _man  _null
    htmlparse	_tcl  _man  _null
    irc		_tcl  _man _exa
    javascript	_tcl  _man  _null
    log		_tcl  _man  _null
    math	 _tci _man  _null
    md5		_tcl  _man  _null
    md4		_tcl  _man  _null
    mime	_tcl  _man _exa
    ncgi	_tcl  _man  _null
    nntp	_tcl  _man _exa
    ntp		_tcl  _man _exa
    pop3	_tcl  _man  _null
    pop3d	_tcl  _man  _null
    profiler	_tcl  _man  _null
    report	_tcl  _man  _null
    sha1	_tcl  _man  _null
    smtpd	_tcl  _man _exa
    soundex	_tcl  _man  _null
    stooop	_tcl  _man  _null
    struct	_tcl  _man _exa
    textutil	 _tex _man  _null
    uri		_tcl  _man  _null
} {
    lappend modules $m
    set guide($m,pkg) $pkg
    set guide($m,doc) $doc
    set guide($m,exa) $exa
}

# --------------------------------------------------------------
