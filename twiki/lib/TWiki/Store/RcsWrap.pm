# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2002 John Talintyre, john.talintyre@btinternet.com
# Copyright (C) 2002-2007 Peter Thoeny, peter@thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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

=pod

---+ package TWiki::Store::RcsWrap

This package does not publish any methods. It implements the
virtual methods of the [[TWikiStoreRcsFileDotPm][TWiki::Store::RcsFile]] superclass.

Wrapper around the RCS commands required by TWiki.
There is one of these object for each file stored under RCS.

=cut

package TWiki::Store::RcsWrap;

use TWiki;
use File::Copy;
use TWiki::Store::RcsFile;
use TWiki::Time;

@ISA = qw(TWiki::Store::RcsFile);

use strict;
use Assert;

# implements RcsFile
sub new {
    my( $class, $session, $web, $topic, $attachment ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;
    my $this =
      bless( new TWiki::Store::RcsFile( $session, $web, $topic, $attachment ),
             $class );
    return $this;
}

=pod

---++ ObjectMethod finish
Complete processing after the client's HTTP request has been responded
to.
   1 breaking circular references to allow garbage collection in persistent
     environments

=cut

sub finish {
    my $this = shift;

}

# implements RcsFile
sub initBinary {
    my( $this ) = @_;

    $this->{binary} = 1;

    TWiki::Store::RcsFile::_mkPathTo( $this->{file} );

    return if -e $this->{rcsFile};

    my ( $rcsOutput, $exit ) =
      $this->{session}->{sandbox}->sysCommand(
          $TWiki::cfg{RCS}{initBinaryCmd}, FILENAME => $this->{file} );
    if( $exit ) {
        throw Error::Simple( $TWiki::cfg{RCS}{initBinaryCmd}.
                               ' of '.$this->_hidePath($this->{file}).
                                 ' failed: '.$rcsOutput );
    } elsif( ! -e $this->{rcsFile} ) {
        # Sometimes (on Windows?) rcs file not formed, so check for it
        throw Error::Simple( $TWiki::cfg{RCS}{initBinaryCmd}.
                               ' of '.$this->_hidePath($this->{rcsFile}).
                                 ' failed to create history file ');
    }
}

# implements RcsFile
sub initText {
    my( $this ) = @_;

    $this->{binary} = 0;

    TWiki::Store::RcsFile::_mkPathTo( $this->{file} );

    return if -e $this->{rcsFile};

    my ( $rcsOutput, $exit ) =
      $this->{session}->{sandbox}->sysCommand
        ( $TWiki::cfg{RCS}{initTextCmd},
          FILENAME => $this->{file} );
    if( $exit ) {
        $rcsOutput ||= '';
        throw Error::Simple( $TWiki::cfg{RCS}{initTextCmd}.
                               ' of '.$this->_hidePath($this->{file}).
                                 ' failed: '.$rcsOutput );
    } elsif( ! -e $this->{rcsFile} ) {
        # Sometimes (on Windows?) rcs file not formed, so check for it
        throw Error::Simple( $TWiki::cfg{RCS}{initTextCmd}.
                               ' of '.$this->_hidePath($this->{rcsFile}).
                                 ' failed to create history file ');
    }
}

# implements RcsFile
sub addRevisionFromText {
    my( $this, $text, $comment, $user, $date ) = @_;
    $this->init();

    unless( -e $this->{rcsFile} ) {
        $this->_lock();
        $this->_ci( $comment, $user, $date );
    }
    $this->_saveFile( $this->{file}, $text );
    $this->_lock();
    $this->_ci( $comment, $user, $date );
}

# implements RcsFile
sub addRevisionFromStream {
    my( $this, $stream, $comment, $user, $date ) = @_;
    $this->init();

    $this->_lock();
    $this->_saveStream( $stream );
    $this->_ci( $comment, $user, $date );
}

# implements RcsFile
sub replaceRevision {
    my( $this, $text, $comment, $user, $date ) = @_;

    my $rev = $this->numRevisions();

    $comment ||= 'none';

    # update repository with same userName and date
    if( $rev == 1 ) {
        # initial revision, so delete repository file and start again
        unlink $this->{rcsFile};
    } else {
        $this->_deleteRevision( $rev );
    }
    $this->_saveFile( $this->{file}, $text );
	$date = TWiki::Time::formatTime( $date , '$rcs', 'gmtime');

    $this->_lock();
    my ($rcsOut, $exit) =
      $this->{session}->{sandbox}->sysCommand(
          $TWiki::cfg{RCS}{ciDateCmd},
          DATE => $date,
          USERNAME => $user,
          FILENAME => $this->{file},
          COMMENT => $comment );
    if( $exit ) {
        $rcsOut = $TWiki::cfg{RCS}{ciDateCmd}."\n".$rcsOut;
        return $rcsOut;
    }
    chmod( $TWiki::cfg{RCS}{filePermission}, $this->{file} );
}

# implements RcsFile
sub deleteRevision {
    my( $this ) = @_;
    my $rev = $this->numRevisions();
    return undef if( $rev <= 1 );
    return $this->_deleteRevision( $rev );
}

sub _deleteRevision {
    my( $this, $rev ) = @_;

    # delete latest revision (unlock (may not be needed), delete revision)
    my ($rcsOut, $exit) =
      $this->{session}->{sandbox}->sysCommand(
          $TWiki::cfg{RCS}{unlockCmd},
          FILENAME => $this->{file} );

    chmod( $TWiki::cfg{RCS}{filePermission}, $this->{file} );

    ($rcsOut, $exit) = $this->{session}->{sandbox}->sysCommand(
        $TWiki::cfg{RCS}{delRevCmd},
        REVISION => '1.'.$rev,
        FILENAME => $this->{file} );

    if( $exit ) {
        throw Error::Simple( $TWiki::cfg{RCS}{delRevCmd}.
                               ' of '.$this->_hidePath($this->{file}).
                                 ' failed: '.$rcsOut );
    }

    # Update the checkout
    $rev--;
    ($rcsOut, $exit) = $this->{session}->{sandbox}->sysCommand(
        $TWiki::cfg{RCS}{coCmd},
        REVISION => '1.'.$rev,
        FILENAME => $this->{file} );

    if( $exit ) {
        throw Error::Simple( $TWiki::cfg{RCS}{coCmd}.
                               ' of '.$this->_hidePath($this->{file}).
                                 ' failed: '.$rcsOut );
    }
    $this->_saveFile( $this->{file}, $rcsOut );
}

# implements RcsFile
sub getRevision {
    my( $this, $version ) = @_;

    unless( $version && -e $this->{rcsFile} ) {
        return $this->SUPER::getRevision( $version );
    }

    my $tmpfile = '';
    my $tmpRevFile = '';
    my $coCmd = $TWiki::cfg{RCS}{coCmd};
    my $file = $this->{file};
    if( $TWiki::cfg{RCS}{coMustCopy} ) {
        # Need to take temporary copy of topic, check it out to file,
        # then read that
        # Need to put RCS into binary mode to avoid extra \r appearing and
        # read from binmode file rather than stdout to avoid early file
        # read termination
        $tmpfile = $this->_mkTmpFilename();
        $tmpRevFile = $tmpfile.',v';
        copy( $this->{rcsFile}, $tmpRevFile );
        my ($tmp, $status) = $this->{session}->{sandbox}->sysCommand(
            $TWiki::cfg{RCS}{tmpBinaryCmd},
            FILENAME => $tmpRevFile );
        $file = $tmpfile;
        $coCmd =~ s/-p%REVISION/-r%REVISION/;
    }
    my ($text, $status) = $this->{session}->{sandbox}->sysCommand(
        $coCmd,
        REVISION => '1.'.$version,
        FILENAME => $file );

    if( $tmpfile ) {
        $text = $this->_readFile( $tmpfile );
        # SMELL: Is untainting really necessary here?
        unlink TWiki::Sandbox::untaintUnchecked( $tmpfile );
        unlink TWiki::Sandbox::untaintUnchecked( $tmpRevFile );
    }

    return $text;
}

sub numRevisions {
    my( $this ) = @_;

    unless( -e $this->{rcsFile}) {
        return 1 if( -e $this->{file} );
        return 0;
    }

    my ($rcsOutput, $exit) =
      $this->{session}->{sandbox}->sysCommand
        ( $TWiki::cfg{RCS}{histCmd},
          FILENAME => $this->{rcsFile} );
    if( $exit ) {
        throw Error::Simple( 'RCS: '.$TWiki::cfg{RCS}{histCmd}.
                               ' of '.$this->_hidePath($this->{rcsFile}).
                                 ' failed: '.$rcsOutput );
    }
    if( $rcsOutput =~ /head:\s+\d+\.(\d+)\n/ ) {
        return $1;
    }
    if( $rcsOutput =~ /total revisions: (\d+)\n/ ) {
        return $1;
    }
    return 1;
}

# implements RcsFile
sub getRevisionInfo {
    my( $this, $version ) = @_;

    if( -e $this->{rcsFile} ) {
        if( !$version || $version > $this->numRevisions()) {
            $version = $this->numRevisions();
        }
        my( $rcsOut, $exit ) = $this->{session}->{sandbox}->sysCommand
          ( $TWiki::cfg{RCS}{infoCmd},
            REVISION => '1.'.$version,
            FILENAME => $this->{rcsFile} );
        if( ! $exit ) {
            if( $rcsOut =~ /^.*?date: ([^;]+);  author: ([^;]*);[^\n]*\n([^\n]*)\n/s ) {
                my $user = $2;
                my $comment = $3;
                my $date = TWiki::Time::parseTime( $1 );
                my $rev = $version;
                if( $rcsOut =~ /revision 1.([0-9]*)/ ) {
                    $rev = $1;
                    return( $rev, $date, $user, $comment );
                }
            }
        }
    }

    return $this->SUPER::getRevisionInfo( $version );
}

# implements RcsFile
sub revisionDiff {
    my( $this, $rev1, $rev2, $contextLines ) = @_;
    my $tmp = '';
    my $exit;
    if ( $rev1 eq '1' && $rev2 eq '1' ) {
        my $text = $this->getRevision(1);
        $tmp = "1a1\n";
        foreach( split( /\r?\n/, $text ) ) {
            $tmp = "$tmp> $_\n";
        }
    } else {
        $contextLines = 3 unless defined($contextLines);
        ( $tmp, $exit ) = $this->{session}->{sandbox}->sysCommand(
            $TWiki::cfg{RCS}{diffCmd},
            REVISION1 => '1.'.$rev1,
            REVISION2 => '1.'.$rev2,
            FILENAME => $this->{rcsFile},
            CONTEXT => $contextLines );
        # comment out because we get a non-zero status for a good result!
        #if( $exit ) {
        #    throw Error::Simple( 'RCS: '.$TWiki::cfg{RCS}{diffCmd}.
        #                           ' failed: '.$! );
        #}
    }
	
    return parseRevisionDiff( $tmp );
}

=pod

---++ StaticMethod parseRevisionDiff( $text ) -> \@diffArray

| Description: | parse the text into an array of diff cells |
| #Description: | unlike Algorithm::Diff I concatinate lines of the same diffType that are sqential (this might be something that should be left up to the renderer) |
| Parameter: =$text= | currently unified or rcsdiff format |
| Return: =\@diffArray= | reference to an array of [ diffType, $right, $left ] |
| TODO: | move into RcsFile and add indirection in Store |

=cut

sub parseRevisionDiff {
    my( $text ) = @_;

    my ( $diffFormat ) = 'normal'; #or rcs, unified...
    my ( @diffArray ) = ();

    $diffFormat = 'unified' if ( $text =~ /^---/s );

    $text =~ s/\r//go;  # cut CR

    my $lineNumber=1;
    if ( $diffFormat eq 'unified' ) {
        foreach( split( /\r?\n/, $text ) ) {
            if ( $lineNumber > 2 ) {   #skip the first 2 lines (filenames)
                if ( /@@ [-+]([0-9]+)([,0-9]+)? [-+]([0-9]+)(,[0-9]+)? @@/ ) {
	    	        #line number
                    push @diffArray, ['l', $1, $3];
                } elsif( /^\-(.*)$/ ) {
                    push @diffArray, ['-', $1, ''];
                } elsif( /^\+(.*)$/ ) {
                    push @diffArray, ['+', '', $1];
                } else {
                    s/^ (.*)$/$1/go;
                    push @diffArray, ['u', $_, $_];
                }
            }
            $lineNumber++;
        }
    } else {
        #'normal' rcsdiff output
        foreach( split( /\r?\n/, $text ) ) {
    	    if ( /^([0-9]+)[0-9\,]*([acd])([0-9]+)/ ) {
    	        #line number
                push @diffArray, ['l', $1, $3];
            } elsif( /^< (.*)$/ ) {
	            push @diffArray, ['-', $1, ''];
            } elsif( /^> (.*)$/ ) {
	            push @diffArray, ['+', '', $1];
            } else {
                #push @diffArray, ['u', '', ''];
            }
        }
    }
    return \@diffArray;
}

sub _ci {
    my( $this, $comment, $user, $date ) = @_;

    $comment = 'none' unless $comment;

    my( $cmd, $rcsOutput, $exit );
    if( defined( $date )) {
        $date = TWiki::Time::formatTime( $date , '$rcs', 'gmtime');
        $cmd = $TWiki::cfg{RCS}{ciDateCmd};
        ($rcsOutput, $exit)= $this->{session}->{sandbox}->sysCommand(
            $cmd,
            USERNAME => $user,
            FILENAME => $this->{file},
            COMMENT => $comment,
            DATE => $date );
    } else {
        $cmd = $TWiki::cfg{RCS}{ciCmd};
        ($rcsOutput, $exit)= $this->{session}->{sandbox}->sysCommand(
            $cmd,
            USERNAME => $user,
            FILENAME => $this->{file},
            COMMENT => $comment );
    }
    $rcsOutput ||= '';

    if( $exit ) {
        throw Error::Simple($cmd.' of '.$this->_hidePath($this->{file}).
                              ' failed: '.$exit.' '.$rcsOutput );
    }

    chmod( $TWiki::cfg{RCS}{filePermission}, $this->{file} );
}

sub _lock {
    my $this = shift;

    return unless -e $this->{rcsFile};

    # Try and get a lock on the file
    my ($rcsOutput, $exit) = $this->{session}->{sandbox}->sysCommand(
        $TWiki::cfg{RCS}{lockCmd}, FILENAME => $this->{file} );

    if( $exit ) {
        # if the lock has been set more than 24h ago, let's try to break it
        # and then retry.  Should not happen unless in Cairo upgrade
        # scenarios - see Item2102
        if ((time - (stat($this->{rcsFile}))[9]) > 3600) {
            warn 'Automatic recovery: breaking lock for ' . $this->{file} ;
            $this->{session}->{sandbox}->sysCommand(
                $TWiki::cfg{RCS}{breaklockCmd}, FILENAME => $this->{file} );
        ($rcsOutput, $exit) = $this->{session}->{sandbox}->sysCommand(
                $TWiki::cfg{RCS}{lockCmd}, FILENAME => $this->{file} );
        }
       if ( $exit ) {
           # still no luck - bailing out
           $rcsOutput ||= '';
           throw Error::Simple( 'RCS: '.$TWiki::cfg{RCS}{lockCmd}.
                                ' failed: '.$rcsOutput );
       }
    }
    chmod( $TWiki::cfg{RCS}{filePermission}, $this->{file} );
}

sub getRevisionAtTime {
    my( $this, $date ) = @_;

    if ( !-e $this->{rcsFile} ) {
        return undef;
    }
	$date = TWiki::Time::formatTime( $date , '$rcs', 'gmtime');
    my ($rcsOutput, $exit) = $this->{session}->{sandbox}->sysCommand(
        $TWiki::cfg{RCS}{rlogDateCmd},
        DATE => $date,
        FILENAME => $this->{file} );

    if ( $rcsOutput =~ m/revision \d+\.(\d+)/ ) {
        return $1;
    }
    return 1;
}

1;
