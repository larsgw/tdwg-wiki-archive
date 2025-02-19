# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2007 Peter Thoeny, peter@thoeny.org
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

---+ package TWiki::Search

This module implements all the search functionality.

=cut

package TWiki::Search;

use strict;
use Assert;
use TWiki::Sandbox;
use TWiki::User;
use TWiki::Time;

my $emptySearch =   'something.Very/unLikelyTo+search-for;-)';

BEGIN {
    # 'Use locale' for internationalisation of Perl sorting and searching - 
    # main locale settings are done in TWiki::setupLocale
    # Do a dynamic 'use locale' for this module
    if( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod

---++ ClassMethod new ($session)

Constructor for the singleton Search engine object.

=cut

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( {}, $class );

    ASSERT($session->isa( 'TWiki')) if DEBUG;
    $this->{session} = $session;

    return $this;
}

# Untaints the search value (text string, regex or search expression) by
# 'filtering in' valid characters only.
sub _filterSearchString {
    my $this = shift;
    my $searchString = shift;
    my $type = shift;

    # Use filtering-out of regexes only if (1) on a safe sandbox platform
    # OR (2) administrator has explicitly configured $forceUnsafeRegexes == 1.
    #
    # Only well-secured intranet sites, authenticated for all access
    # (view, edit, attach, search, etc), AND forced to use unsafe
    # platforms, should use the $forceUnsafeRegexes flag.
    my $unsafePlatform = ( not ($this->{session}->{sandbox}->{SAFE} ) );

    # FIXME: Use of new global
    my $useFilterIn = ($unsafePlatform and not $TWiki::cfg{ForceUnsafeRegexes});

    ########################################################################
    # SMELL: commented out useless condition; $langAlphabetic was always 1,#
    # and is now removed from TWiki.pm. What was this supposed to do?      #
    ########################################################################
    # Non-alphabetic language sites (e.g. Japanese and Chinese) cannot use
    # filtering-in and must use safe pipes, since TWiki does not currently
    # support Unicode, required for filtering-in.  Alphabetic languages such
    # as English, French, Russian, Greek and most European languages are
    # handled by filtering-in.
    #if ( not $TWiki::langAlphabetic and $unsafePlatform ) {
    #    # Best option is to upgrade Perl.
    #    die "You are using a non-alphabetic language on a non-safe-pipes platform.  This is a serious SECURITY RISK,\nso TWiki cannot be used as it is currently installed - please\nread TWiki:Codev/SafePipes for options to avoid or remove this risk.";
    #}

    my $mixedAlphaNum = $TWiki::regex{mixedAlphaNum};

    my $validChars;            # String of valid characters or POSIX
                               # regex elements (e.g. [:alpha:] from 
                               # _setupRegexes) - designed to
                               # be used within a character class.

    if( $type eq 'regex' ) {
        # Regular expression search - example: soap;wsdl;web service;!shampoo;[Ff]red
        if ( $useFilterIn ) {
            # Filter in
            # TWiki search syntax and limited regex syntax
            $validChars = ${mixedAlphaNum}.' !;.[]\\*\\+';
        } else {
            # Filter out - only for use on safe pipe platform or
            # if forced by admin
            # FIXME: Review and test since first versions were broken
            # SMELL: CC commented out next two lines as they escape
            # escape chars in REs
            #$searchString =~ s/(^|[^\\])(['"`\\])/$1\\$2/g;    # Escape all types of quotes and backslashes
            #$searchString =~ s/([\@\$])\(/$1\\\(/g;          # Escape @( ... ) and $( ... )
        }

    } elsif( $type eq 'literal' ) {
        # Filter in
        # Literal search - search for exactly what was typed in (old style
        # TWiki non-regex search)
        # Alphanumeric, spaces, selected punctuation
        $validChars = ${mixedAlphaNum}.' \.';

    } else {
        # FIXME: spaces not working - url encoded in search pattern
        # Filter in
        # Keyword search (new style, Google-like).
        # Example: soap +wsdl +"web service" -shampoo
        $validChars = ${mixedAlphaNum}.' +"-';
    }

    if ( $useFilterIn ) {
        # Clean up - delete all invalid characters
        # FIXME: be sure to escape special characters in literal
        $searchString =~ s/[^${validChars}]+//go;
    }

    # Untaint - same for filtering in and out since already sanitised
    $searchString =~ /^(.*)$/;
    $searchString = $1;

    # Limit string length
    $searchString = substr($searchString, 0, 1500);
}

=pod

---++ StaticMethod getTextPattern (  $text, $pattern  )

Sanitise search pattern - currently used for FormattedSearch only

=cut

sub getTextPattern {
    my( $text, $pattern ) = @_;

    $pattern =~ s/([^\\])([\$\@\%\&\#\'\`\/])/$1\\$2/go;  # escape some special chars
    $pattern = TWiki::Sandbox::untaintUnchecked( $pattern );

    my $OK = 0;
    eval {
       $OK = ( $text =~ s/$pattern/$1/is );
    };
    $text = '' unless( $OK );

    return $text;
}


# Split the search string into tokens depending on type of search.
# Search is an 'AND' of all tokens - various syntaxes implemented
# by this routine.
sub _tokensFromSearchString {
    my( $this, $searchString, $type ) = @_;

    my @tokens = ();
    if( $type eq 'regex' ) {
        # Regular expression search Example: soap;wsdl;web service;!shampoo
        @tokens = split( /;/, $searchString );

    } elsif( $type eq 'literal' ) {
        # Literal search (old style)
        $tokens[0] = $searchString;

    } else {
        # Keyword search (Google-style) - implemented by converting
        # to regex format. Example: soap +wsdl +"web service" -shampoo

        # Prevent tokenizing on spaces in "literal string"
        $searchString =~ s/(\".*?)\"/&_translateSpace($1)/geo;
        $searchString =~ s/[\+\-]\s+//go;

        # Build pattern of stop words
        my $prefs = $this->{session}->{prefs};
        my $stopWords = $prefs->getPreferencesValue( 'SEARCHSTOPWORDS' ) || '';
        $stopWords =~ s/[\s\,]+/\|/go;
        $stopWords =~ s/[\(\)]//go;

        # Tokenize string taking account of literal strings, then remove
        # stop words and convert '+' and '-' syntax.
        @tokens =
            map { s/^\+//o; s/^\-/\!/o; s/^"//o; $_ }    # remove +, change - to !, remove "
            grep { ! /^($stopWords)$/i }                  # remove stopwords
            map { s/$TWiki::TranslationToken/ /go; $_ }   # restore space
            split( /[\s]+/, $searchString );              # split on spaces
    }

    return @tokens;
}

# Convert spaces into translation token characters (typically NULs),
# preventing tokenization.
#
# FIXME: Terminology confusing here!
sub _translateSpace {
    my $text = shift;
    $text =~ s/\s+/$TWiki::TranslationToken/go;
    return $text;
}


# Search a single web based on parameters - @theTokens is a list of
# search terms to be ANDed together, $topic is list of one or more topics.
#
sub _searchTopicsInWeb {
    my( $this, $web, $topic, $scope, $type,
        $caseSensitive, @theTokens ) = @_;

    my @topicList = ();
    return @topicList unless( @theTokens );   # bail out if no search string
    my $store = $this->{session}->{store};

    if( $topic ) {
        # limit search to topic list
        if( $topic =~ /^\^\([\_\-\+$TWiki::regex{mixedAlphaNum}\|]+\)\$$/ ) {
            # topic list without wildcards
            # for speed, do not get all topics in web
            # but convert topic pattern into topic list
            my $topics = $topic;
            $topics =~ s/^\^\(//o;
            $topics =~ s/\)\$//o;
            # build list from topic pattern
            @topicList = split( /\|/, $topics );
        } else {
            # topic list with wildcards
            @topicList = $store->getTopicNames( $web );
            if( $caseSensitive ) {
                # limit by topic name,
                @topicList = grep( /$topic/, @topicList );
            } else {
                # Codev.SearchTopicNameAndTopicText
                @topicList = grep( /$topic/i, @topicList );
            }
        }
    } else {
        @topicList = $store->getTopicNames( $web );
    }

    # default scope is 'text'
    $scope = 'text' unless( $scope =~ /^(topic|all)$/ );

    # AND search - search once for each token, ANDing result together
    foreach my $token ( @theTokens ) {
        # search on each token
        my $invertSearch = ( $token =~ s/^\!//o );
        # flag for AND NOT search
        my @scopeTextList = ();
        my @scopeTopicList = ();
        return @topicList unless( @topicList );

        # scope can be 'topic' (default), 'text' or "all"
        # scope='text', e.g. Perl search on topic name:
        unless( $scope eq 'text' ) {
            my $qtoken = $token;
            # FIXME I18N
            $qtoken = quotemeta( $qtoken ) if( $type ne 'regex' );
            if( $caseSensitive ) {
                # fix for Codev.SearchWithNoPipe
                @scopeTopicList = grep( /$qtoken/, @topicList );
            } else {
                @scopeTopicList = grep( /$qtoken/i, @topicList );
            }
        }

        # scope='text', e.g. grep search on topic text:
        unless( $scope eq 'topic' ) {
            # search only for the topic name, ignoring matching lines.
            # We will make a mess of reporting the matches later on.
            my $matches = $store->searchInWebContent
              ( $token, $web, \@topicList,
                { type => $type, casesensitive => $caseSensitive,
                  files_without_match => 1 } );
            @scopeTextList = keys %$matches;
        }

        if( @scopeTextList && @scopeTopicList ) {
            # join 'topic' and 'text' lists
            push( @scopeTextList, @scopeTopicList );
            my %seen = ();
            # make topics unique
            @scopeTextList = sort grep { ! $seen{$_} ++ } @scopeTextList;
        } elsif( @scopeTopicList ) {
            @scopeTextList =  @scopeTopicList;
        }

        if( $invertSearch ) {
            # do AND NOT search
            my %seen = ();
            foreach my $topic ( @scopeTextList ) {
                $seen{$topic} = 1;
            }
            @scopeTextList = ();
            foreach my $topic ( @topicList ) {
                push( @scopeTextList, $topic ) unless( $seen{$topic} );
            }
        }
        # reduced topic list for next token
        @topicList = @scopeTextList;
    }
    return @topicList;
}

sub _makeTopicPattern {
    my( $topic ) = @_ ;
    return '' unless( $topic );
    # 'Web*, FooBar' ==> ( 'Web*', 'FooBar' ) ==> ( 'Web.*', "FooBar" )
    my @arr = map { s/[^\*\_\-\+$TWiki::regex{mixedAlphaNum}]//go; s/\*/\.\*/go; $_ }
              split( /,\s*/, $topic );
    return '' unless( @arr );
    # ( 'Web.*', 'FooBar' ) ==> "^(Web.*|FooBar)$"
    return '^(' . join( '|', @arr ) . ')$';
}

=pod

---++ ObjectMethod searchWeb (...)

Search one or more webs according to the parameters.

If =_callback= is set, that means the caller wants results as
soon as they are ready. =_callback_ should be set to a reference
to a function which takes =_cbdata= as the first parameter and
remaining parameters the same as 'print'.

If =_callback= is set, the result is always undef. Otherwise the
result is a string containing the rendered search results.

If =inline= is set, then the results are *not* decorated with
the search template head and tail blocks.

Note: If =format= is set, =template= will be ignored.

Note: For legacy, if =regex= is defined, it will force type='regex'

SMELL: If =template= is defined =bookview= will not work

SMELL: it seems that if you define =_callback= or =inline= then you are
	responsible for converting the TML to HTML yourself!
	
FIXME: =callback= cannot work with format parameter (consider format='| $topic |'

=cut

sub searchWeb {
    my $this = shift;
    ASSERT($this->isa( 'TWiki::Search')) if DEBUG;
    my %params = @_;
    my $callback =      $params{_callback};
    my $cbdata =        $params{_cbdata};
    my $baseTopic =     $params{basetopic} || $this->{session}->{topicName};
    my $baseWeb =       $params{baseweb}   || $this->{session}->{webName};
    my $doBookView =    TWiki::isTrue( $params{bookview} );
    my $caseSensitive = TWiki::isTrue( $params{casesensitive} );
    my $excludeTopic =  $params{excludetopic} || '';
    my $doExpandVars =  TWiki::isTrue( $params{expandvariables} );
    my $format =        $params{format} || '';
    my $header =        $params{header};
    my $inline =        $params{inline};
    my $limit =         $params{limit} || '';
    my $doMultiple =    TWiki::isTrue( $params{multiple} );
    my $nonoise =       TWiki::isTrue( $params{nonoise} );
    my $noEmpty =       TWiki::isTrue( $params{noempty}, $nonoise );
    # Note: a defined header overrides noheader
    my $noHeader =
      !defined($header) && TWiki::isTrue( $params{noheader}, $nonoise)
        # Note: This is done for Cairo compatibility
        || (!$header && $format && $inline);

    my $noSearch =      TWiki::isTrue( $params{nosearch}, $nonoise );
    my $noSummary =     TWiki::isTrue( $params{nosummary}, $nonoise );
    my $zeroResults =   1 - TWiki::isTrue( ($params{zeroresults} || 'on'), $nonoise );
    my $noTotal =       TWiki::isTrue( $params{nototal}, $nonoise );
    my $newLine =       $params{newline} || '';
    my $sortOrder =     $params{order} || '';
    my $revSort =       TWiki::isTrue( $params{reverse} );
    my $scope =         $params{scope} || '';
    my $searchString =  $params{search} || $emptySearch;
    my $separator =     $params{separator};
    my $template =      $params{template} || '';
    my $topic =         $params{topic} || '';
    my $type =          $params{type} || '';
    my $webName =       $params{web} || '';
    my $date =          $params{date} || '';
    my $recurse =       $params{'recurse'} || '';
    my $finalTerm =     $inline ? ( $params{nofinalnewline} || 0 ) : 0;

    $baseWeb =~ s/\./\//go;

    my $session = $this->{session};
    my $renderer = $session->{renderer};

    # Limit search results
    if ($limit =~ /(^\d+$)/o) {
        # only digits, all else is the same as
        # an empty string.  "+10" won't work.
        $limit = $1;
    } else {
        # change 'all' to 0, then to big number
        $limit = 0;
    }
    $limit = 32000 unless( $limit );

    $type = 'regex' if( $params{regex} );

    # Filter the search string for security and untaint it 
    $searchString = $this->_filterSearchString( $searchString, $type );

    my $mixedAlpha = $TWiki::regex{mixedAlpha};
    if( defined( $separator )) {
        $separator =~ s/\$n\(\)/\n/gos;  # expand "$n()" to new line
        $separator =~ s/\$n([^$mixedAlpha]|$)/\n$1/gos;
    }
    if( $newLine ) {
        $newLine =~ s/\$n\(\)/\n/gos;  # expand "$n()" to new line
        $newLine =~ s/\$n([^$mixedAlpha]|$)/\n$1/gos;
    }

    my $searchResult = '';
    my $homeWeb = $session->{webName};
    my $homeTopic = $TWiki::cfg{HomeTopicName};
    my $store = $session->{store};

    my %excludeWeb;
    my @tmpWebs;

    # A value of 'all' or 'on' by itself gets all webs,
    # otherwise ignored (unless there is a web called 'All'.)
    my $searchAllFlag = ( $webName =~ /(^|[\,\s])(all|on)([\,\s]|$)/i );

    if( $webName ) {
        foreach my $web ( split( /[\,\s]+/, $webName ) ) {
            $web =~ s#\.#/#go;
            # the web processing loop filters for valid web names,
            # so don't do it here.
            if ( $web =~ s/^-// ) {
                $excludeWeb{$web} = 1;
            } else {
                push( @tmpWebs, $web );
                if( TWiki::isTrue( $recurse ) || $web =~ /^(all|on)$/i ) {
                    my $webarg = ($web =~/^(all|on)$/i) ? undef : $web;
                    push( @tmpWebs,
                      $store->getListOfWebs( 'user,allowed', $webarg ));
                }
            }
        }

    } else {
        # default to current web
        push( @tmpWebs, $session->{webName} );
        if ( TWiki::isTrue( $recurse )) {
            push( @tmpWebs, $store->getListOfWebs( 'user,allowed',
                                                   $session->{webName} ));
        }
    }

    my @webs;
    foreach my $web ( @tmpWebs ) {
        push( @webs, $web ) unless $excludeWeb{$web};
        $excludeWeb{$web} = 1;
    }

    # E.g. "Bug*, *Patch" ==> "^(Bug.*|.*Patch)$"
    $topic = _makeTopicPattern( $topic );

    # E.g. "Web*, FooBar" ==> "^(Web.*|FooBar)$"
    $excludeTopic = _makeTopicPattern( $excludeTopic );

    my $output = '';
    my $tmpl = '';

    my $originalSearch = $searchString;
    my $spacedTopic;

    if( $format ) {
        $template = 'searchformat';
    } elsif( $template ) {
        # template definition overrides book and rename views
    } elsif( $doBookView ) {
        $template = 'searchbookview';
    } else {
        $template = 'search';
    }
    $tmpl = $session->{templates}->readTemplate( $template );

    # SMELL: the only META tags in a template will be METASEARCH
    # Why the heck are they being filtered????
    $tmpl =~ s/\%META{.*?}\%//go;  # remove %META{'parent'}%

    # Split template into 5 sections
    my( $tmplHead, $tmplSearch, $tmplTable, $tmplNumber, $tmplTail ) =
      split( /%SPLIT%/, $tmpl );

    # Invalid template?
    if( ! $tmplTail ) {
        my $mess =
          CGI::h1('TWiki Installation Error') .
              'Incorrect format of '.$template.' template (missing sections? There should be 4 %SPLIT% tags)';
        if ( defined $callback ) {
            &$callback( $cbdata, $mess );
            return undef;
        } else {
            return $mess;
        }
    }

    # Expand tags in template sections
    $tmplSearch = $session->handleCommonTags( $tmplSearch,
                                              $homeWeb,
                                              $homeTopic );
    $tmplNumber = $session->handleCommonTags( $tmplNumber,
                                              $homeWeb,
                                              $homeTopic );

    # If not inline search, also expand tags in head and tail sections
    unless( $inline ) {
        $tmplHead = $session->handleCommonTags( $tmplHead,
                                                $homeWeb,
                                                $homeTopic );

        if( defined $callback ) {
            $tmplHead = $renderer->getRenderedVersion( $tmplHead,
                                                       $homeWeb,
                                                       $homeTopic );
            $tmplHead =~ s|</*nop/*>||goi;   # remove <nop> tags
            &$callback( $cbdata, $tmplHead );
        } else {
            # don't getRenderedVersion; this will be done by a single
            # call at the end.
            $searchResult .= $tmplHead;
        }
    }

    # Generate 'Search:' part showing actual search string used
    unless( $noSearch ) {
        my $searchStr = $searchString;
        $searchStr = '' if( $searchString eq $emptySearch );
        $searchStr =~ s/&/&amp;/go;
        $searchStr =~ s/</&lt;/go;
        $searchStr =~ s/>/&gt;/go;
        $searchStr =~ s/^\.\*$/Index/go;
        $tmplSearch =~ s/%SEARCHSTRING%/$searchStr/go;
        if( defined $callback ) {
            $tmplSearch = $renderer->getRenderedVersion( $tmplSearch,
                                                         $homeWeb,
                                                         $homeTopic );
            $tmplSearch =~ s|</*nop/*>||goi;   # remove <nop> tag
            &$callback( $cbdata, $tmplSearch );
        } else {
            # don't getRenderedVersion; will be done later
            $searchResult .= $tmplSearch;
        }
    }

    # Split the search string into tokens depending on type of search -
    # each token is ANDed together by actual search
    my @tokens = $this->_tokensFromSearchString( $searchString, $type );

    # Write log entry
    # FIXME: Move log entry further down to log actual webs searched
    if( ( $TWiki::cfg{Log}{search} ) && ( ! $inline ) ) {
        my $t = join( ' ', @webs );
        $session->writeLog( 'search', $t, $searchString );
    }

    # Loop through webs
    my $isAdmin = $session->{user}->isAdmin();
    my $ttopics = 0;
    foreach my $web ( @webs ) {
        $web =~ s/$TWiki::cfg{NameFilter}//go;
        $web = TWiki::Sandbox::untaintUnchecked( $web );

        next unless $store->webExists( $web );  # can't process what ain't thar

        my $prefs = $session->{prefs};
        my $thisWebNoSearchAll = $prefs->getWebPreferencesValue( 'NOSEARCHALL', $web ) || '';

        # make sure we can report this web on an 'all' search
        # DON'T filter out unless it's part of an 'all' search.
        next if ( $searchAllFlag
                  && ! $isAdmin
                  && ( $thisWebNoSearchAll =~ /on/i || $web =~ /^[\.\_]/ )
                  && $web ne $session->{webName} );

        # Run the search on topics in this web
        my @topicList = $this->_searchTopicsInWeb(
            $web, $topic, $scope, $type, $caseSensitive, @tokens );

        # exclude topics, Codev.ExcludeWebTopicsFromSearch
        if( $caseSensitive && $excludeTopic ) {
            @topicList = grep( !/$excludeTopic/, @topicList );
        } elsif( $excludeTopic ) {
            @topicList = grep( !/$excludeTopic/i, @topicList );
        }
        next if( $noEmpty && ! @topicList ); # Nothing to show for this web

        my $topicInfo = {};

        # sort the topic list by date, author or topic name, and cache the
        # info extracted to do the sorting
        if( $sortOrder eq 'modified' ) {

            # For performance:
            #   * sort by approx time (to get a rough list)
            #   * shorten list to the limit + some slack
            #   * sort by rev date on shortened list to get the accurate list
            # SMELL: Ciaro had efficient two stage handling of modified sort.
            # SMELL: In Dakar this seems to be pointless since latest rev
            # time is taken from topic instead of dir list.
            my $slack = 10;
            if(  $limit + 2 * $slack < scalar( @topicList ) ) {
                # sort by approx latest rev time
                my @tmpList =
                  map { $_->[1] }
                    sort {$a->[0] <=> $b->[0] }
                      map { [ $store->getTopicLatestRevTime( $web, $_ ), $_ ] }
                        @topicList;
                @tmpList = reverse( @tmpList ) if( $revSort );

                # then shorten list and build the hashes for date and author
                my $idx = $limit + $slack;
                @topicList = ();
                foreach( @tmpList ) {
                    push( @topicList, $_ );
                    $idx -= 1;
                    last if $idx <= 0;
                }
            }

            $topicInfo = $this->_sortTopics( $web, \@topicList,
                                             $sortOrder, !$revSort );
        } elsif( $sortOrder =~ /^creat/ || # topic creation time
                   $sortOrder eq 'editby' || # author
                     $sortOrder =~ s/^formfield\((.*)\)$/$1/ # form field
                    ) {

            $topicInfo = $this->_sortTopics( $web, \@topicList,
                                             $sortOrder, !$revSort );

        } else {

            # simple sort, see Codev.SchwartzianTransformMisused
            # note no extraction of topic info here, as not needed
            # for the sort. Instead it will be read lazily, later on.
            if( $revSort ) {
                @topicList = sort {$b cmp $a} @topicList;
            } else {
                @topicList = sort {$a cmp $b} @topicList;
            }
        }

        if( $date ){
            use TWiki::Time;
            my @ends = &TWiki::Time::parseInterval( $date );
            my @resultList = ();
            foreach my $topic ( @topicList ) {
                # if date falls out of interval: exclude topic from result
                my $topicdate = $store->getTopicLatestRevTime( $web, $topic );
                push( @resultList, $topic )
                  unless ( $topicdate < $ends[0] || $topicdate > $ends[1] );
            }
            @topicList = @resultList;
        }

        # header and footer of $web
        my( $beforeText, $repeatText, $afterText ) =
          split( /%REPEAT%/, $tmplTable );
        if( defined $header ) {
            $beforeText = TWiki::expandStandardEscapes($header);
            $beforeText =~ s/\$web/$web/gos;         # expand name of web
            if( defined( $separator )) {
                $beforeText .= $separator;
            } else {
                $beforeText =~ s/([^\n])$/$1\n/os;  # add new line at end if needed
            }
        }

        # output the list of topics in $web
        my $ntopics = 0;
        my $headerDone = $noHeader;
        foreach my $topic ( @topicList ) {
            my $forceRendering = 0;
            unless( exists( $topicInfo->{$topic} ) ) {
                # not previously cached
                $topicInfo->{$topic} =
                  $this->_extractTopicInfo( $web, $topic, 0, undef );
            }
            my $epochSecs = $topicInfo->{$topic}->{modified};
            my $revDate = TWiki::Time::formatTime( $epochSecs );
            my $isoDate = TWiki::Time::formatTime( $epochSecs, '$iso', 'gmtime');

            my $revUser = $topicInfo->{$topic}->{editby} || 'UnknownUser';
            my $ru = $session->{users}->findUser( $revUser );
            my $revNum  = $topicInfo->{$topic}->{revNum} || 0;

            # Check security
            # FIXME - how do we deal with user login not being available if
            # coming from search script?
            my $allowView = $topicInfo->{$topic}->{allowView};
            next unless $allowView;

            my ( $meta, $text );

            # Special handling for format='...'
            if( $format ) {
                ( $meta, $text ) = $this->_getTextAndMeta( $topicInfo, $web, $topic );

                if( $doExpandVars ) {
                    if( $web eq $baseWeb && $topic eq $baseTopic ) {
                        # primitive way to prevent recursion
                        $text =~ s/%SEARCH/%<nop>SEARCH/g;
                    }
                    $text = $session->handleCommonTags( $text, $web, $topic );
                }
            }

            my @multipleHitLines = ();
            if( $doMultiple ) {
                my $pattern = $tokens[$#tokens]; # last token in an AND search
                $pattern = quotemeta( $pattern ) if( $type ne 'regex' );
                ( $meta, $text ) = $this->_getTextAndMeta( $topicInfo, $web, $topic ) unless $text;
                if( $caseSensitive ) {
                    @multipleHitLines = reverse grep { /$pattern/ } split( /[\n\r]+/, $text );
                } else {
                    @multipleHitLines = reverse grep { /$pattern/i } split( /[\n\r]+/, $text );
                }
            }

            # SMELL: this loop is a rather hairy; why not do it thus:
            # while(scalar(@multipleHitLines))?
            # presumably you are relying on the fact that text will be set
            # when doMultiple is off, even though @multipleHitLines will
            # be empty? I can't work it out.
            do {    # multiple=on loop

                my $out = '';

                $text = pop( @multipleHitLines ) if( scalar( @multipleHitLines ) );

                if( $format ) {
                    $out = $format;
                    $out = TWiki::expandStandardEscapes( $out );
                    $out =~ s/\$web/$web/gs;
                    $out =~ s/\$topic\(([^\)]*)\)/TWiki::Render::breakName( $topic, $1 )/ges;
                    $out =~ s/\$topic/$topic/gs;
                    $out =~ s/\$date/$revDate/gs;
                    $out =~ s/\$isodate/$isoDate/gs;
                    $out =~ s/\$rev/$revNum/gs;
                    $out =~ s/\$wikiusername/$ru->webDotWikiName()/ges;
                    $out =~ s/\$wikiname/$ru->wikiName()/ges;
                    $out =~ s/\$username/$ru->login()/ges;
                    my $r1info = {};
                    $out =~ s/\$createdate/$this->_getRev1Info( $web, $topic, 'date', $r1info )/ges;
                    $out =~ s/\$createusername/$this->_getRev1Info( $web, $topic, 'username', $r1info )/ges;
                    $out =~ s/\$createwikiname/$this->_getRev1Info( $web, $topic, 'wikiname', $r1info )/ges;
                    $out =~ s/\$createwikiusername/$this->_getRev1Info( $web, $topic, 'wikiusername', $r1info )/ges;
                    if( $out =~ m/\$text/ ) {
                        ( $meta, $text ) = $this->_getTextAndMeta( $topicInfo, $web, $topic ) unless $text;
                        if( $topic eq $session->{topicName} ) {
                            # defuse SEARCH in current topic to prevent loop
                            $text =~ s/%SEARCH{.*?}%/SEARCH{...}/go;
                        }
                        $out =~ s/\$text/$text/gos;
                        $forceRendering = 1 unless( $doMultiple );
                    }
                } else {
                    $out = $repeatText;
                }
                $out =~ s/%WEB%/$web/go;
                $out =~ s/%TOPICNAME%/$topic/go;
                $out =~ s/%TIME%/$revDate/o;

                my $srev = 'r' . $revNum;
                if( $revNum eq '0' || $revNum eq '1' ) {
                    $srev = CGI::span( { class => 'twikiNew' }, ($this->{session}->{i18n}->maketext('NEW')) );
                }
                $out =~ s/%REVISION%/$srev/o;
                $out =~ s/%AUTHOR%/$revUser/o;

                if( ( $inline || $format ) && ( ! ( $forceRendering ) ) ) {
                    # do nothing
                } else {
                    # don't callback yet because of table
                    # rendering
                    #$out = $session->handleCommonTags( $out, $web, $topic );
                    #$out = $renderer->getRenderedVersion( $out, $web, $topic );
                }

                if( $doBookView ) {
                    # BookView
                    ( $meta, $text ) = $this->_getTextAndMeta( $topicInfo, $web, $topic ) unless $text;
                    if( $web eq $baseWeb && $topic eq $baseTopic ) {
                        # primitive way to prevent recursion
                        $text =~ s/%SEARCH/%<nop>SEARCH/g;
                    }
                    $text = $session->handleCommonTags( $text, $web, $topic );
                    $text = $session->{renderer}->getRenderedVersion
                      ( $text, $web, $topic );
                    # FIXME: What about meta data rendering?
                    $out =~ s/%TEXTHEAD%/$text/go;

                } elsif( $format ) {
                    $out =~ s/\$summary(?:\(([^\)]*)\))?/$renderer->makeTopicSummary( $text, $topic, $web, $1 )/ges;
                    $out =~ s/\$changes(?:\(([^\)]*)\))?/$renderer->summariseChanges($ru,$web,$topic,$1,$revNum)/ges;
                    $out =~ s/\$formfield\(\s*([^\)]*)\s*\)/TWiki::Render::renderFormFieldArg( $meta, $1 )/ges;
                    $out =~ s/\$parent\(([^\)]*)\)/TWiki::Render::breakName( $meta->getParent(), $1 )/ges;
                    $out =~ s/\$parent/$meta->getParent()/ges;
                    $out =~ s/\$formname/$meta->getFormName()/ges;
                    $out =~ s/\$count\((.*?\s*\.\*)\)/_countPattern( $text, $1 )/ges;
                    # FIXME: Allow all regex characters but escape them
                    # Note: The RE requires a .* at the end of a pattern to avoid false positives
                    # in pattern matching
                    $out =~ s/\$pattern\((.*?\s*\.\*)\)/getTextPattern( $text, $1 )/ges;
                    $out =~ s/\r?\n/$newLine/gos if( $newLine );
                    if( defined( $separator )) {
                        $out .= $separator;
                    } else {
                        # add new line at end if needed
                        # SMELL: why?
                        $out =~ s/([^\n])$/$1\n/s;
                    }

                } elsif( $noSummary ) {
                    $out =~ s/%TEXTHEAD%//go;
                    $out =~ s/&nbsp;//go;

                } else {
                    # regular search view
                    ( $meta, $text ) = $this->_getTextAndMeta(
                        $topicInfo, $web, $topic ) unless $text;
                    $text = $renderer->makeTopicSummary( $text, $topic, $web );
                    $out =~ s/%TEXTHEAD%/$text/go;
                }

                # lazy output of header (only if needed for the first time)
                unless( $headerDone ) {
                    $headerDone = 1;
                    my $prefs = $session->{prefs};
                    my $thisWebBGColor =
                      $prefs->getWebPreferencesValue( 'WEBBGCOLOR', $web ) ||
                        '\#FF00FF';
                    $beforeText =~ s/%WEBBGCOLOR%/$thisWebBGColor/go;
                    $beforeText =~ s/%WEB%/$web/go;
                    $beforeText = $session->handleCommonTags
                      ( $beforeText, $web, $topic );
                    if ( defined $callback ) {
                        $beforeText =
                          $renderer->getRenderedVersion(
                              $beforeText, $web, $topic );
                        $beforeText =~ s|</*nop/*>||goi;   # remove <nop> tag
                        &$callback( $cbdata, $beforeText );
                    } else {
                        $searchResult .= $beforeText;
                    }
                }

		#don't expand if a format is specified - it breaks tables and stuff 
                unless(  $format ) {
                    $out =
                      $renderer->getRenderedVersion( $out, $web, $topic );
                }

                # output topic (or line if multiple=on)
                if ( defined $callback ) {
                    $out =~ s|</*nop/*>||goi;   # remove <nop> tag
                    &$callback( $cbdata, $out );
                } else {
                    $searchResult .= $out;
                }

            } while( @multipleHitLines ); # multiple=on loop

            $ntopics += 1;
            $ttopics += 1;

            # delete topic info to clear any cached data
            undef $topicInfo->{$topic};

            last if( $ntopics >= $limit );
        } # end topic loop

        # output footer only if hits in web
        if( $ntopics ) {
            # output footer of $web
            $afterText  = $session->handleCommonTags( $afterText,
                                                      $web,
                                                      $homeTopic );
            if( $inline || $format ) {
                $afterText =~ s/\n$//os;  # remove trailing new line
            }

            if ( defined $callback ) {
                $afterText = 
                  $renderer->getRenderedVersion( $afterText,
                                                         $web,
                                                         $homeTopic );
                $afterText =~ s|</*nop/*>||goi;   # remove <nop> tag
                &$callback( $cbdata, $afterText );
            } else {
                $searchResult .= $afterText;
            }
        }

        # output number of topics (only if hits in web or if
        # only searching one web)
        if( $ntopics || scalar( @webs ) < 2 ) {
            unless( $noTotal ) {
                my $thisNumber = $tmplNumber;
                $thisNumber =~ s/%NTOPICS%/$ntopics/go;
                if ( defined $callback ) {
                    $thisNumber =
                      $renderer->getRenderedVersion( $thisNumber,
                                                             $web,
                                                             $homeTopic );
                    $thisNumber =~ s|</*nop/*>||goi;   # remove <nop> tag
                    &$callback( $cbdata, $thisNumber );
                } else {
                    $searchResult .= $thisNumber;
                }
            }
        }
    } # end of: foreach my $web ( @webs )
    return '' if ( $ttopics == 0 && $zeroResults );

    if( $format  && ! $finalTerm ) {
        if( $separator ) {
            $searchResult =~ s/$separator$//s;  # remove separator at end
        } else {
            $searchResult =~ s/\n$//os;            # remove trailing new line
        }
    }

    unless( $inline ) {
        $tmplTail = $session->handleCommonTags( $tmplTail,
                                                $homeWeb,
                                                $homeTopic );

        if( defined $callback ) {
            $tmplTail = $renderer->getRenderedVersion( $tmplTail,
                                                       $homeWeb,
                                                       $homeTopic );
            $tmplTail =~ s|</*nop/*>||goi;   # remove <nop> tag
            &$callback( $cbdata, $tmplTail );
        } else {
            $searchResult .= $tmplTail;
        }
    }

    return undef if ( defined $callback );
    return $searchResult if $inline;

    $searchResult = $session->handleCommonTags( $searchResult,
                                                $homeWeb,
                                                $homeTopic );
    $searchResult = $renderer->getRenderedVersion( $searchResult,
                                                   $homeWeb,
                                                   $homeTopic );

    return $searchResult;
}

# extract topic info required for sorting and sort.
sub _sortTopics{
    my ( $this, $web, $topics, $sortfield, $revSort ) = @_;

    my $topicInfo = {};
    foreach my $topic ( @$topics ) {
        $topicInfo->{$topic} = $this->_extractTopicInfo( $web, $topic, $sortfield );
    }
    if( $revSort ) {
        @$topics = map { $_->[1] }
          sort { _compare( $b->[0], $a->[0] ) }
            map { [ $topicInfo->{$_}->{$sortfield}, $_ ] }
              @$topics;
    } else {
        @$topics = map { $_->[1] }
          sort { _compare( $a->[0], $b->[0] ) }
            map { [ $topicInfo->{$_}->{$sortfield}, $_ ] }
              @$topics;
    }

    return $topicInfo;
}

# RE for a full-spec floating-point number
my $number = qr/^[-+]?[0-9]+(\.[0-9]*)?([Ee][-+]?[0-9]+)?$/s;

sub _compare {
    if( $_[0] =~ /$number/o && $_[1] =~ /$number/o ) {
        # when sorting numbers do it largest first; this is just because
        # this is what date comparisons need.
        return $_[1] <=> $_[0];
    } else {
        return $_[1] cmp $_[0];
    }
}

# extract topic info
sub _extractTopicInfo {
    my ( $this, $web, $topic, $sortfield ) = @_;
    my $info = {};
    my $session = $this->{session};
    my $store = $session->{store};

    my ( $meta, $text ) = $this->_getTextAndMeta( undef, $web, $topic );

    $info->{text} = $text;
    $info->{meta} = $meta;

    my ( $revdate, $revuser, $revnum ) = $meta->getRevisionInfo();
    $info->{editby}     = $revuser ? $revuser->webDotWikiName() : '';
    $info->{modified}   = $revdate;
    $info->{revNum}     = $revnum;

    $info->{allowView} =
      $session->{security}->
        checkAccessPermission( 'view', $session->{user},
                               $text, $meta,
                               $topic, $web );

    return $info unless $sortfield;

    if ( $sortfield =~ /^creat/ ) {
        ( $info->{$sortfield} ) = $meta->getRevisionInfo( 1 );
    } elsif ( !defined( $info->{$sortfield} )) {
        $info->{$sortfield} = TWiki::Render::renderFormFieldArg( $meta, $sortfield );
    }

    return $info;
}

# get the text and meta for a topic
sub _getTextAndMeta {
    my( $this, $topicInfo, $web, $topic ) = @_;
    my ( $meta, $text );
    my $store = $this->{session}->{store};

    # read from cache if it's there
    if ( $topicInfo ) {
        $text = $topicInfo->{$topic}->{text};
        $meta = $topicInfo->{$topic}->{meta};
    }

    unless( defined $text ) {
        ( $meta, $text ) =
          $store->readTopic( undef, $web, $topic, undef );
        $text =~ s/%WEB%/$web/gos;
        $text =~ s/%TOPIC%/$topic/gos;
    }
    return ( $meta, $text );
}

# Returns the topic revision info of the base version,
# attributes are 'date', 'username', 'wikiname',
# 'wikiusername'. Revision info is cached in the search
# object for speed.
sub _getRev1Info {
    my( $this, $web, $topic, $attr, $info ) = @_;
    my $key = $web.'.'.$topic;
    my $store = $this->{session}->{store};

    unless( $info->{webTopic} && $info->{webTopic} eq $key ) {
        my $meta = new TWiki::Meta( $this->{session}, $web, $topic );
        my ( $d, $u ) = $meta->getRevisionInfo( 1 );
        $info->{date} = $d;
        $info->{user} = $u;
        $info->{webTopic} = $key;
    }
    if( $attr eq 'username' ) {
        return $info->{user}->login();
    }
    if( $attr eq 'wikiname' ) {
        return $info->{user}->wikiName();
    }
    if( $attr eq 'wikiusername' ) {
        return $info->{user}->webDotWikiName();
    }
    if( $attr eq 'date' ) {
        return TWiki::Time::formatTime( $info->{date} );
    }

    return 1;
}

# With the same argument as $pattern, returns a number which is the count of
# occurences of the pattern argument.
sub _countPattern {
    my( $theText, $thePattern ) = @_;

    $thePattern =~ s/([^\\])([\$\@\%\&\#\'\`\/])/$1\\$2/go;  # escape some special chars
    $thePattern =~ /(.*)/;     # untaint
    $thePattern = $1;
    my $OK = 0;
    eval {
        # counting hack, see: http://dev.perl.org/perl6/rfc/110.html
        $OK = () = $theText =~ /$thePattern/g;
    };

    return $OK;
}

1;
