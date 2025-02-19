head	1.3;
access;
symbols;
locks; strict;
comment	@# @;


1.3
date	2004.11.23.03.03.49;	author TWikiGuest;	state Exp;
branches;
next	1.2;

1.2
date	2003.09.28.17.35.00;	author BobMorris;	state Exp;
branches;
next	1.1;

1.1
date	2003.09.22.21.17.43;	author KevinThiele;	state Exp;
branches;
next	;


desc
@none
@


1.3
log
@testenv
@
text
@%META:TOPICINFO{author="GregorHagedorn" date="1085758493" format="1.0" version="1.3"}%
%META:TOPICPARENT{name="OptionalAndRequiredElements"}%
&lt;Terminology&gt; At the very least, an SDD document without a Terminology element can have no structured descriptions in the &lt;Descriptions&gt; element. However, it may still be useful to allow an SDD document to have unstructured (freetext) descriptions only, in which case a Terminology element is not necessary?

-- Main.KevinThiele - 22 Sep 2003

Actually, in Schema version 0.62, if a Descriptions section has nothing in it but <nop>NaturalLanguageDescription (i.e. freetext) elements, it is possible (though not necessary) that it will never make a reference to anything in the Terminology element. In this case, I suppose a Terminology section is not needed, although it is not optional in 0.62

As you well know, I am not a fan of natural language in an exchange format, believing it belongs to the application processing the instance document. However, a fair bit has been invested in supporting both and that seems to need ways of mixing them. So a <nop>NaturalLanguageDescription object _could_ have Character objects (i.e. keyrefs to <nop>Character objects) mixed with free text (Wording objects) and HTML formatting. In this circumstance, I would still argue that there should only be one place <nop>Character definitions should live, namely the Terminology section. In other words, tempting as it might seem to allow Character definitions in the places where they are used, my intuition is that there will be less application programming effort if all definitions are in the Terminology section. So a hybrid description will still need a Terminology section, but pure freetext (<nop>NaturalLanguageDescription objects with no descendent Character objects) might not. That said, an application has to be prepared to do something meaningful on any mixture of freetext and coded descriptions and so very little will be gained by permitting Terminology to be optional.

-- Main.BobMorris - 28 Sep 2003

%META:TOPICMOVED{by="GregorHagedorn" date="1085758493" from="SDD.CommentOnOptionalityForTerminologyElement" to="SDD.ClosedTopicOptionalityTerminologyElement"}%
@


1.2
log
@none
@
text
@d1 1
a1 1
%META:TOPICINFO{author="BobMorris" date="1064770500" format="1.0" version="1.2"}%
d13 1
@


1.1
log
@none
@
text
@d1 1
a1 1
%META:TOPICINFO{author="KevinThiele" date="1064265462" format="1.0" version="1.1"}%
d6 7
@
