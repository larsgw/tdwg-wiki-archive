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
#
# This is both the factory for UIs and the base class of UI constructors.
# A UI is the V part of the MVC model used in configure.
#
# Each structural entity in a configure screen has a UI type, either
# stored directly in the entity or indirectly in the type associated
# with a value. The UI type is used to guide a visitor which is run
# over the structure to generate the UI.
#
use strict;

package TWiki::Configure::UI;

use vars qw ($totwarnings $toterrors);

sub new {
    my ($class, $item) = @_;

    my $this = bless( {}, $class);
    Carp::confess unless $item;
    $this->{item} = $item;

    return $this;
}

# Static UI factory
# UIs *must* exist
sub loadUI {
    my ($id, $item) = @_;

    $id = 'TWiki::Configure::UIs::'.$id;
    my $ui;
    eval "use $id; \$ui = new $id(\$item);";

    return undef if (!$ui && $@);

    return $ui;
}

# Static checker factory
# Checkers *need not* exist
sub loadChecker {
    my ($id, $item) = @_;
    $id =~ s/}{/::/g;
    $id =~ s/[}{]//g;
    $id =~ s/'//g;
    $id =~ s/-/_/g;
    my $checkClass = 'TWiki::Configure::Checkers::'.$id;
    my $checker;

    eval "use $checkClass; \$checker = new $checkClass(\$item);";
    # Can't locate errors are OK
    die $@ if ($@ && $@ !~ /Can't locate /);

    return $checker;
}

# Basic unauthenticated tcp HTTP 1.0 get on port 80
# dies on any failure
sub getUrl {
    my ($this, $url) = @_;

    die "Bad URL $url " unless $url =~ m#^(\w+)://(.*?)(/.*)$#;
    my ($protocol, $host, $path) = ($1, $2, $3);
    my $port = 80;
    if ($host =~ s/:(\d+)$//) {
        $port = $1;
    }
    my $req = "GET $path HTTP/1.0\r\nHost: $host\r\nUser-agent: TWikiConfigure/1.0 +http://twiki.org/\r\n\r\n";
    if ($TWiki::cfg{PROXY}{HOST} && $TWiki::cfg{PROXY}{PORT}) {
        $req = "GET http://$host:$port$path HTTP/1.0\r\n\r\n";
        $host = $TWiki::cfg{PROXY}{HOST};
        $port = $TWiki::cfg{PROXY}{PORT};
    }

    require Socket;

    my $ipaddr = Socket::inet_aton($host);
    die "inet_aton: host cannot be found" unless $ipaddr;
    my $packedaddr = Socket::sockaddr_in( $port, $ipaddr );
    my $proto = getprotobyname('tcp');
    die "getprotobyname: No proto" unless $proto;
    unless (socket(*SOCK, &Socket::PF_INET, &Socket::SOCK_STREAM, $proto)) {
        die "socket: $!.";
    }
    unless (connect(*SOCK, $packedaddr)) {
        die "connect: $!.\n$req";
    }
    select SOCK;
    local $| = 1;
    local $/ = undef;
    print SOCK $req;
    my $result = <SOCK>;
    close( SOCK );
    select STDOUT;
    return $result;
}

# STATIC Used by a whole bunch of things that just need to show a key-value row
# (called as a method, i.e. with class as first parameter)
sub setting {
    my $this = shift;
    my $key = shift;
    return CGI::Tr(CGI::td({class=>'firstCol'}, $key).
                   CGI::td({class=>'secondCol'}, join(' ', @_)))."\n";
}

# Generate a foldable block (twisty). This is a DIV with a table in it
# that contains the settings and doc rows.
sub foldableBlock {
    my( $this, $head, $attr, $body ) = @_;
    my $headText = $head . CGI::span({ class => 'blockLinkAttribute' }, $attr);
    $body = CGI::start_table({width => '100%', -border => 0, -cellspacing => 0, -cellpadding => 0}).$body.CGI::end_table();
    my $mess = $this->collectMessages($this->{item});

    my $anchor = $this->_makeAnchor( $head );
    my $id = $anchor;
    my $blockId = $id;
    my $linkId = 'blockLink'.$id;
    my $linkAnchor = $anchor.'link';
    return CGI::a({ name => $linkAnchor }).
      CGI::a({id => $linkId,
              class => 'blockLink blockLinkOff',
              href => '#'.$linkAnchor,
              rel => 'nofollow',
              onclick => 'foldBlock("' . $id . '"); return false;'
             },
             $headText.$mess).
               CGI::div( {id => $blockId,
                          class=> 'foldableBlock foldableBlockClosed'
                         }, $body ).
                           "\n";
}

# encode a string to make an HTML anchor
sub _makeAnchor {
    my ($this, $str) = @_;

    $str =~ s/\s(\w)/uc($1)/ge;
    $str =~ s/\W//g;
    return $str;
}

sub NOTE {
    my $this = shift;
    return CGI::p({class=>"info"}, join("\n",@_));
}

# a warning
sub WARN {
    my $this = shift;
    $this->{item}->inc('warnings');
    $totwarnings++;
    return CGI::div(CGI::span({class=>'warn'},
                              CGI::strong('Warning: ').join("\n",@_)));
}

# an error
sub ERROR {
    my $this = shift;
    $this->{item}->inc('errors');
    $toterrors++;
    return CGI::div(CGI::span({class=>'error'},
                              CGI::strong('Error: ').join("\n",@_)));
}

# Used in place of CGI::hidden, which is broken in some versions.
# Assumes $name does not need to be encoded
# HTML encodes the value
sub hidden {
    my ($this, $name, $value) = @_;
    $value ||= '';
    $value =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge;
	return '<input type="hidden" name="'.$name.'" value="'.$value.'" />';
}

# Invoked to confirm authorisation, and handle password changes. The password
# is changed in $TWiki::cfg, a change which is then detected and written when
# the configuration file is actually saved.
sub authorised {
    my $pass = $TWiki::query->param('cfgAccess');

    # The first time we get here is after the "next" button is hit. A password
    # won't have been defined yet; so the authorisation must fail to force
    # a prompt.
    if (!defined($pass)) {
        if (!$TWiki::cfg{Password}) {
            # No password passed in, and TWiki::cfg doesn't contain a password
            # Suggest that a password should be set.
            print CGI::div({class=>'error'}, <<'HERE');
WARNING: You have not defined a password. Your TWiki can be reconfigured
by anyone who can run <code>configure</code>!
HERE
        }
        return 0;
    }

    # If we get this far, a password has been given. Check it.
    if ($TWiki::cfg{Password} &&
          crypt($pass, $TWiki::cfg{Password}) ne $TWiki::cfg{Password}) {
        print CGI::div({class=>'error'}, "Password incorrect");
        return 0;
    }

    # Password is correct, or no password has been defined.
    # Change the password if so requested
    my $newPass = $TWiki::query->param('newCfgP');

    if ($newPass) {
        my $confPass = $TWiki::query->param('confCfgP') || '';
        if ($newPass ne $confPass) {
            print CGI::div({class=>'error'},
              'New password and confirmation do not match');
            return 0;
        }
        $TWiki::cfg{Password} = _encode($newPass);
        print CGI::div({class=>'error'}, 'Password changed');
    }

    return 1;
}


sub collectMessages {
    my $this = shift;
    my ($item)  =  @_;

    my $warnings      =  $item->{warnings} || 0;
    my $errors        =  $item->{errors} || 0;
    my $errorsMess    =  "$errors error"     .  (($errors   > 1) ? 's' : '');
    my $warningsMess  =  "$warnings warning" .  (($warnings > 1) ? 's' : '');
    my $mess          =  '';
    $mess .= ' ' . CGI::span({class=>'error'}, $errorsMess) if $errors;
    $mess .= ' ' . CGI::span({class=>'warn'}, $warningsMess) if $warnings;

    return $mess;
}

sub _encode {
    my $pass = shift;
    my @saltchars = ( 'a'..'z', 'A'..'Z', '0'..'9', '.', '/' );
    my $salt = $saltchars[int(rand($#saltchars+1))] .
      $saltchars[int(rand($#saltchars+1)) ];
    return crypt($pass, $salt);
}

1;
