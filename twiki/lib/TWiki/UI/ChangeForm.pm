# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
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

---+ package TWiki::UI::ChangeForm

Service functions used by the UI packages

=cut

package TWiki::UI::ChangeForm;

use strict;
use Error qw( :try );
use Assert;
use CGI::Carp qw( fatalsToBrowser );
use CGI qw( :cgi -any );
use TWiki;
use TWiki::OopsException;

=pod

---+ ClassMethod generate( $session, $theWeb, $theTopic, $editaction )

Generate the page that supports selection of the form.

=cut

sub generate {
    my( $session, $web, $topic, $editaction ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    my $page = $session->{templates}->readTemplate( 'changeform' );
    my $q = $session->{cgiQuery};

    my $store = $session->{store};
    my $formName = $q->param( 'formtemplate' ) || '';
    unless( $formName ) {
        my( $meta, $tmp ) = $store->readTopic( undef, $web, $topic, undef );
        my $form = $meta->get( 'FORM' );
        $formName = $form->{name} if $form;
    }
    $formName = 'none' if( !$formName );

    my $prefs = $session->{prefs};
    my $legalForms = $prefs->getWebPreferencesValue( 'WEBFORMS', $web );
    $legalForms =~ s/^\s*//;
    $legalForms =~ s/\s*$//;
    my @forms = split( /[,\s]+/, $legalForms );
    unshift @forms, 'none';

    my $formList = '';
    my $formElemCount = 0;
    foreach my $form ( @forms ) {
    	$formElemCount++;
        $formList .= CGI::br() if( $formList );
        my $formElemId = 'formtemplateelem' . $formElemCount;
        my $props = {
            type => 'radio',
            name => 'formtemplate',
            id => $formElemId,
            value => $form
           };
        $props->{checked} = 'checked' if $form eq $formName;
        $formList .= CGI::input( $props );
	my ($formWeb, $formTopic) = $session->normalizeWebTopicName($web, $form);
        my $formLabelContent = '&nbsp;' . ( $store->topicExists( $formWeb, $formTopic ) ? 
	  '[['.$formWeb.'.'.$formTopic.']['.$form.']]' : $form );
        $formList .= CGI::label( { for => $formElemId}, $formLabelContent );
    }
    $page =~ s/%FORMLIST%/$formList/go;

    my $parent = $q->param( 'topicparent' ) || '';
    $page =~ s/%TOPICPARENT%/$parent/go;

    my $redirectTo = $q->param( 'redirectto' ) || '';
    $page =~ s/%REDIRECTTO%/$redirectTo/go;

    $page = $session->handleCommonTags( $page, $web, $topic );
    $page = $session->{renderer}->getRenderedVersion( $page, $web, $topic );

    my $text = CGI::hidden( -name => 'text', -value => $q->param( 'text' ) );
    $page =~ s/%TEXT%/$text/go;
    $text = '';
    #$text = CGI::hidden( -name => 'action', -value => $editaction ) if $editaction;
    $text .= "<input type=\"hidden\" name=\"action\" value=\"$editaction\" />" if $editaction;
    $page =~ s/%EDITACTION%/$text/go;

    return $page;
}
1;
