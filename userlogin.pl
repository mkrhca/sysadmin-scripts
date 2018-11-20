#!/usr/bin/env perl
#
# Description   : Extract users login history for Linux boxes
#

require strict;


format STDOUT_TOP =
.
format STDOUT =
@<<<<<<<<<<< @|||||| @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$userid, $count, $lastsession
.

my $last        = "/usr/bin/last |egrep -v '\(root|boot|wtmp|^\$\)' ";
my $hostname    = qx(/bin/uname -n);
chomp($hostname);

print "-"x50, "\n";
print "Server - $hostname\n";
print "-"x50, "\n";


open(LAST, "$last |") or die "Can't execute $!\n";
while(<LAST>) {
        if (/^([^ ]+)\s+\S+\/\d+\s+([^ ]+)\s+(.*)$/) {
                $person = $1;
                $remote = $2;
                $date   = $3;
        }
        $logins{$person} = $logins{$person} + 1;
        if ( ! $dest{$person} ) {
                $dest{$person} = "$remote \@ $date";
        }
}
close(LAST);

$userid = "User ID";
$count  = "Count";
$lastsession = "Last active session";
write;

foreach $key (sort keys %logins) {
        $userid = $key;
        $count  = $logins{$key};
        $lastsession = $dest{$key};
        write;
}


__END__
