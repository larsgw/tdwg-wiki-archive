# Copyright (C) 2005 ILOG http://www.ilog.fr
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of the TWiki distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

=pod

---+ package TWiki::Plugins::WysiwygPlugin::HTML2TML;

Convertor for translating HTML into TML (TWiki Meta Language)

The conversion is done by parsing the HTML and generating a parse
tree, and then converting that parse treeinto TML.

The class is a subclass of HTML::Parser, run in XML mode, so it
should be tolerant to many syntax errors, and will also handle
XHTML syntax.

The translator tries hard to make good use of newlines in the
HTML, in order to maintain text level formating that isn't
reflected in the HTML. So the parser retains newlines and
spaces, rather than throwing them away, and uses various
heuristics to determine which to keep when generating
the final TML.

=cut

package TWiki::Plugins::WysiwygPlugin::HTML2TML;

use strict;

use TWiki::Plugins::WysiwygPlugin::HTML2TML::Node;
use TWiki::Plugins::WysiwygPlugin::HTML2TML::Leaf;
use HTML::Parser;

@TWiki::Plugins::WysiwygPlugin::HTML2TML::ISA = ( 'HTML::Parser' );

=pod

---++ ClassMethod new()

Constructs a new HTML to TML convertor.

You *must* provide parseWikiUrl and convertImage if you want URLs
translated back to wikinames. See WysiwygPlugin.pm for an example
of how to call it.

=cut

sub new {
    my( $class ) = @_;

    my $this = new HTML::Parser( start_h => [\&_openTag, 'self,tagname,attr' ],
                                 end_h => [\&_closeTag, 'self,tagname'],
                                 declaration_h => [\&_ignore, 'self'],
                                 default_h => [\&_text, 'self,text'],
                                 comment_h => [\&_comment, 'self,text'] );

    $this = bless( $this, $class );

    $this->xml_mode( 1 );
    $this->unbroken_text( 1 );

    return $this;
}

sub _resetStack {
    my $this = shift;

    $this->{stackTop} =
      new TWiki::Plugins::WysiwygPlugin::HTML2TML::Node( $this->{opts}, '' );
    $this->{stack} = ();
}

=pod

---++ ObjectMethod convert( $html ) -> $tml

Convert a block of HTML text into TML.

=cut

sub convert {
    my( $this, $text, $options ) = @_;

    $this->{opts} = $options;

    my $opts = 0;
    $opts = $WC::VERY_CLEAN
      if ( $options->{very_clean} );

    # SMELL: ought to convert to site charset

    # get rid of nasties
    $text =~ s/\r//g;
    $text =~ s/\t/ /g;
    $this->_resetStack();
    $this->parse( $text );
    $this->eof();
    $this->_apply( undef );
    return $this->{stackTop}->rootGenerate( $opts );
}

# Support autoclose of the tags that are most typically incorrectly
# nested. Autoclose triggers when a second tag of the same type is
# seen without the first tag being closed.
my %autoclose = ( 'li' => 1, 'td' => 1, 'th' => 1, 'tr' => 1 );

sub _openTag {
    my( $this, $tag, $attrs ) = @_;
    if( $autoclose{ lc( $tag )} &&
          $this->{stackTop} &&
            lc($this->{stackTop}->{tag}) eq lc($tag) ) {
        $this->_apply( $tag );
    }

    push( @{$this->{stack}}, $this->{stackTop} ) if $this->{stackTop};
    $this->{stackTop} =
      new TWiki::Plugins::WysiwygPlugin::HTML2TML::Node( $this->{opts}, $tag, $attrs );
}

sub _closeTag {
    my( $this, $tag ) = @_;

    $this->_apply( $tag );
}

sub _text {
    my( $this, $text ) = @_;
    my $l = new TWiki::Plugins::WysiwygPlugin::HTML2TML::Leaf( $text );
    $this->{stackTop}->addChild( $l );
}

sub _comment {
    my( $this, $text ) = @_;
    my $l = new TWiki::Plugins::WysiwygPlugin::HTML2TML::Leaf( $text );
    $this->{stackTop}->addChild( $l );
}

sub _ignore {
}

sub _apply {
    my( $this, $tag ) = @_;

    while( $this->{stack} && scalar( @{$this->{stack}} )) {
        my $top = $this->{stackTop};
        $this->{stackTop} = pop( @{$this->{stack}} );
        die unless $this->{stackTop};
        $this->{stackTop}->addChild( $top );
        last if( $tag && $top->{tag} eq $tag );
    }
}

1;
