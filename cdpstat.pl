#!/usr/bin/perl -w

# 
# Tested on Solaris 8 & 10, some releases of Redhat and AIX.
# 


use strict;
use Getopt::Long;
use Data::Dumper;


sub showhelp {
    printf "Usage: cdpstat -h [-i <iface> ]\n";
    printf "  -i <iface>  Network interface\n";
    printf "  -v          Verbose packet data\n";
    printf "  -h          This help message\n";
    exit 1;
}

sub hex_to_ascii ($) {
    ## Convert the two digit hex number to an ASCII character
    ( my $str = shift ) =~ s/([a-fA-F0-9]{2})/chr(hex $1)/eg;
    return $str;
}

sub runcmd {
    local $| = 1;

    my ( $cmd, $timeout ) = @_;
    my $flagfile = "/tmp/cdptimer.$$" ;

    ## Run the command, exit with the commands exit value
    my $snooppid = fork;

    if ( !$snooppid ) {
        close(STDOUT);
        close(STDERR);
        exec split(/\s+/,$cmd);
        exit ; # should never get here.
    }

    ##Run the watcher, exit 1 if we kill something, 0 otherwise
    my $timerpid = fork;
    if ( !$timerpid ) {
        sleep $timeout;
        my $snoopcmd = kill( 0, $snooppid );
        if ($snoopcmd){
            kill( 'TERM', $snooppid );
            open(TIMER,">$flagfile") or die "Cannot write file: $!\n";
            print TIMER "killed\n";
            close(TIMER);
        }
        exit 0;
    }

    ##Wait for snooppid and reap it
    my $cmdrv = waitpid( $snooppid, 0 );
    my ( $cmdrc, $cmderr ) = ( $?, $! );


    my ( $cmdexit, $cmdsig, $cmddump )
        = ( $cmdrc >> 8, $cmdrc & 127, $cmdrc & 128 );

    ##Kill the timer if its still running, and ensure it gets reaped.
    my $timercmd = kill( 0, $timerpid );
    kill( 'TERM', $timerpid ) if ($timercmd);
    waitpid( $timerpid, 0 );

    if ( -f $flagfile ){
        ##Exit 9 if timerpid killed the snooppid
        unlink($flagfile);
        return 9;
    }
    return $cmdexit;
} # runcmd


sub get_packet {
    ## Solaris 8 snoop returns 1 on error, and 1 if our filter matches a packet :(
    ## Solaris 10 snoop seems to exit proper codes.
    ## AIX oslevel 5200, tcpdump takes another 60s to exit after capturing a packet.
    ## So, we run the timer longer.
    ## We will exit here more perl like; 0=fail 1=true

    my ( $interface, $file ) = @_;
    my $opts;
    my $timeout = 65;
    my $cmd;

   if ( $^O eq 'linux' or $^O eq 'aix' ) {
        my $tcpdump = "/usr/sbin/tcpdump";
        die ("Failed to access $tcpdump: $!\n") unless -x $tcpdump;
        if ( $^O eq 'linux' ) {
            $opts = "-i $interface -XX -s 0 -c 1 ether[20:2] = 0x2000 -w $file";
        }
        else {
            my $oslevel = "/usr/bin/oslevel";
            die "Failed to access $oslevel: $!\n" unless -x $oslevel;
            if ( qx($oslevel -r) =~ /5200/)  {
                $opts = "-I -x -c 1 -i $interface -s 1500 -w $file
                    ether host 01:00:0c:cc:cc:cc and ether[20:2] = 0x2000";
                $timeout = 130;
            }
            else {
                $opts = "-x -c 1 -i $interface -s 0 -w $file
                    ether host 01:00:0c:cc:cc:cc and ether[20:2] = 0x2000";
            }
        }
        $cmd  = "$tcpdump $opts";
        my $return_status = runcmd( $cmd, $timeout );
        return $return_status if ( $return_status == 9 );
        $return_status ? return 0 : return 1;
    }
    elsif ( $^O eq 'solaris' ) {
        ## Solaris 8 snoop always returns 1 for some reason, so cant use the checking above here :(
        my $snoop = "/usr/sbin/snoop";
        die ("Failed to access $snoop: $!\n") unless -x $snoop;
        $opts = "ether 01:00:0c:cc:cc:cc and ether[20:2] = 0x2000";
        $opts = "-x 0 -c 1 -d $interface -o $file $opts";
        $cmd  = "$snoop $opts";
        my $return_status = runcmd( $cmd, $timeout );
        return $return_status if ( $return_status == 9 );

        ## swap the return codes 0 and 1 if Solaris 10
        $return_status ? return 0 : return 1 if ( qx(uname -r) == 5.10 );
        return $return_status;
    }
}  ## get_packet

sub informme {
    my ( $helpmsg, @hexes ) = @_;
    my $mailer = '/usr/sbin/sendmail -t';
    my $me = "jyothirajputhan.purayil\@sc.com";

    if ( open MAIL,"|$mailer" ){
       print MAIL "To: $me\n";
       print MAIL "Subject: " . qx(hostname) . " - $helpmsg\n";
       print MAIL join( ' ', @hexes ) . "\n";
       close MAIL;
    }
    else {
       print "START__\n${helpmsg}\n";
       print "please send the output from START__ to END__ to Jo\n";
       print join( ' ', @hexes );
       print "\nEND__\n";
    }
}

sub validate_iface {

    # Return values:
    #
    # 20 - Virtual          19 - Solaris virtual
    # 18 - Down             17 - Not attached
    # 16 - Unrecognised      1 - Up / Link state not checked
    #

    my ( $interface ) = @_;
    my ($link_check, $link_check_cmd, $link_up_str, $link_down_str);
    my $status = 1;

    ## Interface names starts as these strings will just be ignored.
    #my @logical_ifaces = qw( lo bond veth );
    my @logical_ifaces = qw( lo veth );
    foreach my $virtual_if (@logical_ifaces){
        return 20 if ( $interface =~ m/^$virtual_if/ )
    }

    if ( $^O eq 'solaris' ) {
        $link_check = "/opt/bin/scbinterfaces";
        $link_check_cmd = "$link_check check $interface 2>/dev/null";
        $link_up_str = "$interface is UP";
        $link_down_str = "$interface is DOWN";

        return 19 if ( $interface =~ /:/ );
    }
    elsif ( $^O eq 'linux' ) {
        # Once the bonding is configured I can't see the CDP packet on ethX interfaces
        # So let it check the bond interface
        return 1 if ( $interface =~ /bond/ );
        $link_check = "/sbin/ethtool";
        $link_check_cmd = "$link_check $interface 2>/dev/null | grep -i 'Link detected'";
        $link_up_str = "yes";
        $link_down_str = "no";
    }
    elsif ( $^O eq 'aix' ) {
       $link_check = "/usr/bin/entstat";
       $link_check_cmd = "$link_check -d $interface 2>/dev/null | grep -i 'Link Status'";
       $link_up_str = "up";
       $link_down_str = "down";

    }
    else {
        die ("$^O is not supported OS\n");
    }

    ## Proceed even if we can't get the link state
    return 1 unless ( -x $link_check );

    my $link_stat = qx($link_check_cmd);

    if ( $link_stat =~ /$link_down_str/i ) { $status = 18 }
    elsif ( $^O eq 'aix' ) { $status = 17 if ( qx(/etc/ifconfig -l -u 2>/dev/null) !~ /$interface/ ) }
    elsif ( $link_stat !~ /$link_up_str/i ) { $status = 16 }

    return $status;

} # validate_iface


sub get_cdpdata {

    my ( $interface, $cdpdata_href ) = @_;

    ## Check we have perms.
    die ("Must be Root\n") if ($>);

    # Validate the interface.
    my $ifstatus = validate_iface( $interface );

    if ($ifstatus == 20) { $cdpdata_href->{ERROR} = 'Virtual interface cannot be checked' }
    elsif ($ifstatus == 19) { $cdpdata_href->{ERROR} = 'Cannot snoop the virtual interface in Solaris' }
    elsif ($ifstatus == 18) { $cdpdata_href->{ERROR} = 'Link is Down' }
    elsif ($ifstatus == 17) { $cdpdata_href->{ERROR} = 'Interface is not attached' }
    elsif ($ifstatus == 16) { $cdpdata_href->{ERROR} = 'Please check the Interface' }

    return 0 if ( $ifstatus != 1 );

    my $file = "/tmp/cdpsnoop.tmp.$$";
    my $status = get_packet( $interface, $file );

    ## Check exit status of get_packet and act accordingly.
    if ( $status == 0 or not -f $file ) {
        $cdpdata_href->{ERROR}
            = 'Packet capturing command returned error';
        unlink $file if ( -e $file );
        return 0;
    }
    elsif ( $status == 9 ) {
        $cdpdata_href->{ERROR} = "CDP packet not found";
        unlink $file if ( -e $file );
        return 0;
    }

    # Start processing the packet
    #
    if ( !open( CDPPACKET, $file ) ) {
        $cdpdata_href->{ERROR}
            = "INTERNAL ERROR: Cannot open the file we just created";
        unlink($file) if ( -e $file );
        return 0;
    }

    my $packetdata;
    { local $/; $packetdata = <CDPPACKET>; }
    my @hexes = unpack( "H2" x length($packetdata), $packetdata );

    close(CDPPACKET);

    ## Find the start of the CDP packet, dump the preamble
    my $tempindex = index( join( "", @hexes ), "01000ccccccc" );

    ## Return false if index returns negative number (failure)
    if ( $tempindex < 0 ) {
        $$cdpdata_href{'ERROR'}
            = "Cannot find start of packet for $interface, check $file";
        #unlink($file) if ( -e $file );
        return 0;
    }

    ## Return false if index returns an odd value (data should start at byte boundary)
    if ( $tempindex % 2 ) {
        $$cdpdata_href{'ERROR'}
            = "Start of packet not on byte boundary for $interface, check $file";
        unlink($file) if ( -e $file );
        return 0;
    }

    unlink($file) if ( -e $file );
    splice @hexes, 0, $tempindex / 2;

    ##get cdpver,ttl,checksum starting at byte 22
    $$cdpdata_href{'cdpver'}   = hex $hexes[22];
    $$cdpdata_href{'ttl'}      = hex $hexes[23];
    $$cdpdata_href{'checksum'} = @hexes[ 24 .. 25 ];
    ##start at byte 26
    my $offset = 26;

    TRIPLE:
    while ( $offset < scalar(@hexes) ) {
        ##most errors like "Use of uninitialized value in join or string at"
        ##are caused by bytes of padding at the end of the packet, so the
        ##last TRIPLE lines below are attempts to catch them

        ##last if not at least 5 bytes
        last TRIPLE if ( $offset + 4 > scalar(@hexes) );
        my $id  = hex( $hexes[$offset] ) * 256 + hex( $hexes[ $offset + 1 ] );
        my $len = hex( $hexes[ $offset + 2 ] ) * 256
            + hex( $hexes[ $offset + 3 ] );
        ##last if not enought bytes to match the len specification
        last TRIPLE if ( $offset + $len > scalar(@hexes) );
        ##last if a duplicate id found
        last TRIPLE if ( exists $$cdpdata_href{$id} );

        my $string
            = ( join( '', @hexes[ $offset + 4 .. $offset + $len - 1 ] ) );

        ## ID 0, 2 and 7 need special handling
        if ( $id == 2 ) {
            ##Not sure I got this right, so if we breach offset+len then stop
            my $recordstart = $offset + 4;
            my $nextrecord  = $offset + $len;
            my %foundtypes;
            my %addresshash;
            my $totallen;
            while ( $recordstart lt $nextrecord ) {
                my $protocoltype = hex( $hexes[$recordstart] );
                if ( $protocoltype == 0 ) {
                    #
                    $foundtypes{'snmp'}++;
                    my $addresskey = "snmp" . $foundtypes{'snmp'};
                    my $ba         = hex( $hexes[$recordstart] );
                    my $bb         = hex( $hexes[ $recordstart + 1 ] );
                    my $bc         = hex( $hexes[ $recordstart + 2 ] );
                    my $bd         = hex( $hexes[ $recordstart + 3 ] );
                    $addresshash{$addresskey} = "$ba.$bb.$bc.$bd";
                    $totallen = 4;
                }
                elsif ( $protocoltype == 1 ) {
                    ## PROTOCOL TYPE 1
                    my $protocollength = hex( $hexes[ $recordstart + 1 ] );
                    my $protocol       = $hexes[ $recordstart + 2 ];
                    my $protocoladdresslength
                        = hex( $hexes[ $recordstart + 3 ] ) * 256
                        + hex( $hexes[ $recordstart + 4 ] );
                    if ( $protocol eq "81" ) {
                        $foundtypes{'isoclns'}++;
                        my $addresskey = "isoclns" . $foundtypes{'isoclns'};
                        $addresshash{$addresskey} = join(
                            '',
                            $hexes[
                                  $recordstart
                                + 5 .. $recordstart + 4
                                + $protocoladdresslength
                            ]
                        );
                        $totallen
                            = 4 + $protocollength + $protocoladdresslength;
                    }
                    elsif ( $protocol eq "cc" ) {
                        $foundtypes{'ip'}++;
                        my $addresskey = "ip" . $foundtypes{'ip'};
                        my $ba         = hex( $hexes[ $recordstart + 5 ] );
                        my $bb         = hex( $hexes[ $recordstart + 6 ] );
                        my $bc         = hex( $hexes[ $recordstart + 7 ] );
                        my $bd         = hex( $hexes[ $recordstart + 8 ] );
                        $addresshash{$addresskey} = "$ba.$bb.$bc.$bd";
                        $totallen
                            = 4 + $protocollength + $protocoladdresslength;
                    }
                    else {
                        ## not expected
                        print
                            "unknown protocol, in protocoltype 1, bailing from id 2\n";
                        $offset = $nextrecord;
                        next TRIPLE;
                    }
                }
                elsif ( $protocoltype == 2 ) {
                    ## PROTOCOL TYPE 2
                    $foundtypes{'802'}++;

                    informme(
                        "unimplemented protocoltype 2, bailing from id 2",
                        @hexes );
                    $offset = $nextrecord;
                    next TRIPLE;
                }
                else {
                    ## not expected
                    informme(
                        "unexpected protocoltype $protocoltype, bailing from id 2",
                        @hexes
                    );
                    $offset = $nextrecord;
                    next TRIPLE;
                }

                $recordstart += $totallen;
                if ( $recordstart gt $nextrecord ) {
                    ## something went wrong, jump to next triple
                    informme(
                        "unexpected jump beyond end of record, bailing from this triple",
                        @hexes
                    );
                    $offset = $nextrecord;
                    next TRIPLE;
                }
            }
            $$cdpdata_href{'addresses'} = \%addresshash;
        }
        if ( $id == 7 ) {
            if ( $len == 0 ) {
                ## no net prefixes
                $$cdpdata_href{'ipnetprefix'} = "";
                $offset += 4;
                next TRIPLE;
            }
            else {
                my %netprefixes;
                my $start      = $offset + 4;
                my $netpre_key = 0;
                while ( $start < $offset + $len ) {
                    my $oa         = hex( $hexes[$start] );
                    my $ob         = hex( $hexes[ $start + 1 ] );
                    my $oc         = hex( $hexes[ $start + 2 ] );
                    my $od         = hex( $hexes[ $start + 3 ] );
                    my $bitmask    = hex( $hexes[ $start + 4 ] );
                    my $netpre_val = sprintf "%s.%s.%s.%s/%s", $oa, $ob, $oc,
                        $od, $bitmask;
                    $netprefixes{$netpre_key} = $netpre_val;
                    $netpre_key++;
                    $start += 5;
                }
                $$cdpdata_href{'ipnetprefix'} = \%netprefixes;
            }
        }
        if ( $id == 0 ) {

            ##$$cdpdata_href{'ERROR'}
            ##   = "Found a packet with an id=0 entry, be careful of results";

            $len = 5;
        }

        ##
        ## ID 1,3,4,5,6,9,10,11 are straightforward and known
        $$cdpdata_href{'deviceid'} = hex_to_ascii("$string") if ( $id == 1 );
        $$cdpdata_href{'port'}     = hex_to_ascii("$string") if ( $id == 3 );
        $$cdpdata_href{'capabilities'} = hex("$string") if ( $id == 4 );
        $$cdpdata_href{'version'}  = hex_to_ascii("$string") if ( $id == 5 );
        $$cdpdata_href{'platform'} = hex_to_ascii("$string") if ( $id == 6 );
        $$cdpdata_href{'vtp'}      = hex_to_ascii("$string") if ( $id == 9 );
        $$cdpdata_href{'vlan'}     = hex("$string")          if ( $id == 10 );
        $$cdpdata_href{'sw_duplex'} = hex("$string") if ( $id == 11 );
        ##
        ## Everything else is unknown and could screw up the function.
        if ( $id == 8 || $id > 11 ) {
            my $key = sprintf "unknownid_%s_len_%s", $id, $len - 4;
            if ( $len == 5 ) {
                $$cdpdata_href{$key} = $string;
            }
            else {
                $$cdpdata_href{$key} = hex_to_ascii("$string");
            }
        }

        $offset = $offset + $len;
    }
    ## cdpver 1 does not show duplex
    $$cdpdata_href{'duplex'} = '?' if ( $$cdpdata_href{'cdpver'} == 1 );
    return 1;
} # get_cdpdata


#
# Main
#

my @interfaces;
my $opt_help = 0;
my $verbose  = 0;
my %ifresults;

GetOptions(
    "interface=s" => \@interfaces,
    "verbose+"    => \$verbose,
    "help|?+"   => \$opt_help,
);

showhelp if ( $opt_help || ( !scalar(@interfaces) ) );

#Process each interface
foreach my $interface (@interfaces) {
    my %cdpdata ;

    ## Add this interface as key (with value cdpdata hash) to the global ifresults hash
    $ifresults{$interface} = \%cdpdata;

    ## Get info from cdp packet and store in cdpdata hash
    get_cdpdata( $interface, \%cdpdata );

}

if ($verbose) {
    ## Dump all the data
    print Dumper \%ifresults;
}
elsif ( keys %ifresults ) {

    # We got some data to show.
    printf "%-8s%-40s%-25s%-5s\n", "NIC", "Switch", "Port", "Vlan";
    foreach my $inface ( keys %ifresults ) {

        # Check if an Error wasnt set..
        if ( defined $ifresults{$inface}->{ERROR} ){
            printf "%-8s",  $inface;
            printf "%s\n",  $ifresults{$inface}->{ERROR};
        }

        if ( defined $ifresults{$inface}->{deviceid} ){
            printf "%-8s",  $inface;
            printf "%-40s", $ifresults{$inface}->{deviceid};
            printf "%-25s", $ifresults{$inface}->{port};
            printf "%-5s",  $ifresults{$inface}->{vlan};
            print "\n";
        }
    }
}
