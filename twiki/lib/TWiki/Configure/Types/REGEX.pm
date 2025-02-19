#
# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2006 TWiki Contributors.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.
package TWiki::Configure::Types::REGEX;

use strict;

use TWiki::Configure::Types::STRING;

use base 'TWiki::Configure::Types::STRING';

sub prompt {
    my( $this, $id, $opts, $value ) = @_;
    $value = "$value";
    while ($value =~ s/^\(\?-xism:(.*)\)$/$1/) { };
    $value =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge;
    my $res = '<input name="'.$id.'" type="text" size="55%" value="'.$value.'" />';
    return $res;
}

sub string2value {
    my ($this, $value) = @_;
    while ($value =~ s/^\(\?-xism:(.*)\)$/$1/) { };
    return qr/$value/;
}

sub equals {
    my ($this, $val, $def) = @_;
    while ($val =~ s/^\(\?-xism:(.*)\)$/$1/) {
    }
    while ($def =~ s/^\(\?-xism:(.*)\)$/$1/) {
    }
    if (!defined $val) {
        return 0 if defined $def;
        return 1;
    } elsif (!defined $def) {
        return 0;
    }
    return $val eq $def;
}

1;
