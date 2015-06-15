# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# macports_libsolv.tcl
# $Id$
#
# Copyright (c) 2015 Jackson Isaac <ijackson@macports.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of The MacPorts Project nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

package provide macports_libsolv 1.0
package require macports 1.0
# Load solv.dylib, bindings for libsolv
package require solv

namespace eval macports::libsolv {

    ## Variable for pool
    variable pool

    ## Variable for portindexinfo
    variable portindexinfo

    ## Some debugging related printing of variable contents
    proc print {} {
        variable pool
        puts $solv::Job_SOLVER_SOLVABLE
        puts $pool
        
        set si [$pool cget -solvables]
        puts "-------Printing Pool solvables------"
        while {[set s [$si __next__]] ne "NULL"} {
            puts "$s: [$s __str__]"
        }
    }

    ## Procedure to create the libsolv pool. This is similar to PortIndex. \
    #  Read the PortIndex contents and write into libsolv readable solv's.
    #  To Do:
    #  Add additional information regarding version, description, dependency, etc to solv.
    proc create_pool {} {
        variable pool
        variable portindexinfo

        ## Check if libsolv cache (pool) is already created or not.
        if {![info exists pool]} {
            global macports::sources

            ## Create a new pool instance by calling Pool contructor.
            set pool [solv::Pool]

            foreach source $sources {
                set source [lindex $source 0]
                ## Add a repo in the pool for each source as mentioned in sources.conf
                set repo [$pool add_repo $source]
 
                if {[catch {set fd [open [macports::getindex $source] r]} result]} {
                    ui_warn "Can't open index file for source: $source"
                } else {
                    try {
                        while {[gets $fd line] >= 0} {
                            # Create a solvable for each port processed.
                            set solvable [$repo add_solvable]
                            
                            array unset portinfo
                            set name [lindex $line 0]
                            set len  [lindex $line 1]
                            set line [read $fd $len]
                            
                            $solvable configure -name $name

                            ## Set portinfo of each solv object. Map it to correct solvid.
                            set portindexinfo([$solvable cget -id]) $line
                        }
                    } catch * {
                        ui_warn "It looks like your PortIndex file for $source may be corrupt."
                        throw
                    } finally {
                        close $fd
                    }
                }
            }
            ## createwhatprovides creates hash over all the provides of the package \
            #  This method is necessary before we can run any lookups on provides.
            $pool createwhatprovides
        } else {
            return {}
        }
    }

    ## Search using libsolv. Needs some more work.
    #  To Do list:
    #  Add more info to the solv's to search into more details of the ports (description, \
    #  license, version, etc.
    #  Done:
    #  Add support for search options i.e. --exact, --case-sensitive, --glob, --regex.
    #  Return portinfo to mportsearch which will pass the info to port.tcl to print results.
    proc search {pattern {case_sensitive yes} {matchstyle regexp}  } {
        variable pool
        variable portindexinfo

        set matches [list]
        set sel [$pool Selection]
       
        ## Initialize search option flag depending on the option passed to port search
        switch -- $matchstyle {
            exact {
                set di_flag [expr $solv::Dataiterator_SEARCH_STRING]
            }
            glob {
                set di_flag [expr $solv::Dataiterator_SEARCH_GLOB]
            }
            regexp {
                set di_flag [expr $solv::Dataiterator_SEARCH_REGEX]
            }
            default {
                return -code error "mportsearch: Unsupported matching style: ${matchstyle}."
            }
        }

        ## If --case-sensitive is not passed, Binary OR "|" with no_case flag.
        if {!${case_sensitive}} {
            set di_flag [expr $di_flag | $solv::Dataiterator_SEARCH_NOCASE]
        }
        
        set di [$pool Dataiterator $solv::SOLVABLE_NAME $pattern $di_flag]

        while {[set data [$di __next__]] ne "NULL"} { 
            $sel add_raw $solv::Job_SOLVER_SOLVABLE [$data cget -solvid]
        }

        ## This prints all the solvable's information that matched the pattern.
        foreach s [$sel solvables] {
            lappend matches [$s cget -name]
            lappend matches $portindexinfo([$s cget -id])
        }

        return $matches
    }
}
