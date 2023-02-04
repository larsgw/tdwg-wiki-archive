{
    const INDENT = '  '
    const ICON_PATH = '/pub/TWiki06x01/TWikiDocGraphics/'
    const NUMBERED_TYPE_CHARACTERS = {
        // '1' is default
        'A': 'upper-alpha',
        'a': 'lower-alpha',
        'I': 'upper-roman',
        'i': 'lower-roman'
    }
    function escapeHtml (html) {
        return html.replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
    }
    function makeAutoLink (href) {
        if (/\.(jpe?g|png|gif)$/.test(href)) {
            return `<a href="${href}"><img src="${href}"/></a>`
        }
        return `<a href="${href}">${href}</a>`
    }
    var autolink = true
    var indentLevel = 1
}

File
    = NL* document:Document NL* { return document }
    / NL* { return '' }

Document
    = left:Block NL rest:File { return left + '\n\n' + rest }
    / left:Paragraph NL (&Block / NL) rest:File { return left + '\n\n' + rest }
    / Block
    / Paragraph

Block
    = Header
    / Separator
    / List
    / DefinitionList
    // / Table // TODO
    / Anchor
    / !Tag content:Html &NL { return content }

Paragraph
    = content:ParagraphLines { return `<p>${content}</p>` }

ParagraphLines
    = left:Text NL !Block rest:ParagraphLines { return left + ' ' + rest }
    / left:Text { return left }

// Headers
Header
    = '---' '-'* level:'+'+ include:'!!'? text:Text {
        return `<h${level.length}>${text}</h${level.length}>`
    }

// Separators
Separator
    = '---' '-'* { return '<hr>' }

// Lists
List
    = items:ListItems {
        const type = items[0].type
        const tag = type.type === 'numbered' ? 'ol' : 'ul'
        let attributes = ''
        if (type.type === 'numbered' && type.typeCharacter in NUMBERED_TYPE_CHARACTERS) {
            const listStyle = NUMBERED_TYPE_CHARACTERS[type.typeCharacter]
            attributes = ` style="list-style-type: ${listStyle};"`
        }
        const content = items.map(item => item.html).join('\n')
        const prefix = INDENT.repeat(2 * indentLevel - 2)
        return `${prefix}<${tag}${attributes}>\n${content}\n${prefix}</${tag}>`
    }

ListItems
    = item:ListItem NL items:ListItems { return [item, ...items] }
    / item:ListItem { return [item] }

ListItem
    = indent:ListIndent type:ListType ' ' text:Text rest:ListText* sub:SubList? {
        indentLevel = indent.length

        text = [text, ...rest].join(' ')
        const prefix = INDENT.repeat(2 * indentLevel - 2)

        let attributes = ''
        if (type.type === 'icon') {
            attributes = ` style="list-style-image: url(${ICON_PATH}${type.icon}.gif);"`
        }

        let html
        if (sub) {
            html = [
                `${prefix}${INDENT}<li${attributes}>`,
                `${prefix}${INDENT}${INDENT}${text}`,
                sub,
                `${prefix}${INDENT}</li>`
            ].join('\n')
        } else {
            html = `${prefix}${INDENT}<li${attributes}>${text}</li>`
        }
        return { html, type }
    }

ListType
    = typeCharacter:[1AaIi] '.' { return { type: 'numbered', typeCharacter } }
    / '* icon:' icon:$[a-z-]+ { return { type: 'icon', icon } }
    / '*' { return { type: 'bulleted' } }

ListText
    = NL ListIndent ' '* !('* ' / [1AaIi] '.') text:Text { return text }

SubList
    = NL &{ indentLevel++; return true } items:List { return items }

ListIndent
    = indent:Indent* &{ return indent.length === indentLevel } { return indent }

// Definition list
DefinitionList
    = defs:Definitions { return `<dl>\n${defs.join('\n\n')}\n</dl>` }

Definitions
    = def:Definition NL defs:Definitions { return [def, ...defs] }
    / def:Definition { return [def] }

Definition
    = Indent '$ ' term:$[^:\r\n]+ ': ' def:Text {
        return `${INDENT}<dt>${term}</dt>\n${INDENT}<dd>${def}</dd>`
    }

// Anchor
Anchor
    = '#' name:WikiWord text:(' ' Text)? {
        return `<a name="${name}"></a>${text ? text.join('') : ''}`
    }

// Text
Text
    = text:TextUnit+ { return text.join('') }

TextUnit
    = EscapedLink / Link / Span / Tag / Html / [^\r\n]

Tag
    = NoAutolink / Verbatim / Literal / Sticky

NoAutolink
    = '<noautolink>' { autolink = false; return '' }
    / '</noautolink>' { autolink = true; return '' }

Verbatim
    = '<verbatim>' '\n'? content:$([^<]+ / !'</verbatim>' .)+ '</verbatim>' {
        return `<pre><code>${escapeHtml(content)}</code></pre>`
    }

Literal
    = '<literal>' content:$([^<]+ / !'</literal>' .)+ '</literal>' {
        return content
    }

Sticky
    = ('<sticky>' / '</sticky>') { return '' }

EscapedLink
    = '!' text:$Link { return text }

Link
    = &{ return autolink } link:SafeWikiWordLink path:$('/' [^\r\n ]+) {
        const href = link.href.slice(0, -5) + path
        return makeAutoLink(href)
    }
    / &{ return autolink } link:SafeWikiWordLink { return `<a href="${link.href}">${link.label}</a>` }
    / href:$(LinkProtocol '://' [^\r\n ]+) { return makeAutoLink(href) }
    / '[[' link:ForcedLink ']]' { return `<a href="${link.href}">${link.label}</a>` }
    / '[[' link:ForcedLink '][' label:LinkLabel ']]' { return `<a href="${link.href}">${label}</a>` }
    / '@' handle:$[A-Z]i+ { return `<a href="https://twitter.com/${handle}">@${handle}</a>` }
    // TODO topic title links
    // Non-standard/deprecated
    / '[[' link:ForcedLink ' ' label:LinkLabel ']]' { return `<a href="${link.href}">${label}</a>` }
    / '[[' link:ForcedLink '][' label:LinkLabel '][Name:_blank]]' {
        return `<a href="${link.href}">${label}</a>`
    }

ForcedLink
    = link:WikiWordLink suffix:$([#?/] [^\]]*)? { return { href: link.href + suffix, label: link.label + suffix } }
    / href:$((!'. ' [^\r\n\] ])+) { return { href, label: href } }

SafeWikiWordLink
    = &(
        link:WikiWordLink
        &{ return options.links.includes(link.href) }
    ) link:WikiWordLink {
        return link
    }

WikiWordLink
    = link:WikiWordPathStart {
        const currentDepth = options.context.ATTACHURL.split('/').length
        const prefix = '../'.repeat(currentDepth - 1)
        return { href: prefix + link.href, label: link.label }
    }
    / href:WikiWord { return { href: href + '.html', label: href } }

WikiWordPathStart
    = left:$([A-Z] [a-zA-Z0-9_]*) '.' rest:WikiWordPath {
        return { href: left + '/' + rest.href, label: left + '.' + rest.label }
    }

WikiWordPath
    = WikiWordPathStart
    / href:$([A-Z] [a-zA-Z0-9_]*) {
        return { href: href + '.html', label: href }
    }

LinkLabel
    = label:(Tag / Html / [^\]])* { return label.join('') }

LinkProtocol
    = 'file' / 'ftp' / 'gopher' / 'https' / 'http'
    / 'irc' / 'mailto' / 'news' / 'nntp' / 'telnet'

Span
    = BoldFixed
    / Fixed
    / BoldItalic
    / Italic
    / Bold

BoldFixed
    = '==' !' ' text:(!'==' SpanTextUnit)+ '==' ![a-z0-9]i {
        return `<b><code>${text.flat().join('')}</code></b>`
    }

Fixed
    = '=' !' ' text:(!'=' SpanTextUnit)+ '=' ![a-z0-9=]i {
        return `<code>${text.flat().join('')}</code>`
    }

BoldItalic
    = '__' !' ' text:(!'__' SpanTextUnit)+ '__' ![a-z0-9]i {
        return `<b><i>${text.flat().join('')}</i></b>`
    }

Italic
    = '_' !' ' text:(!'_' SpanTextUnit)+ '_' ![a-z0-9_]i {
        return `<i>${text.flat().join('')}</i>`
    }

Bold
    = '*' !' ' text:(!'*' SpanTextUnit)+ '*' ![a-z0-9]i {
        return `<b>${text.flat().join('')}</b>`
    }

SpanTextUnit
    = !' ' text:TextUnit { return text } / ' '

// General utilities
WikiWord
    = $([A-Z]+ [a-z0-9]+ [A-Z]+ [a-zA-Z0-9_]*)

NL
    = ('\r\n' / '\n' / '\r') { return '\n' }

Indent
    = '   '
    / '\t' { return '   ' }

// Html
Html
    = begin:HtmlTagBegin
    content:(
        $[^<]+
        /
        !(end:HtmlTagEnd &{ return begin.tag === end }) content:HtmlContent {
            return content
        }
    )*
    end:HtmlTagEnd &{ return begin.tag === end } {
        return `<${begin.tag}${begin.attributes || '' }>${content.join('')}</${begin.tag}>`
    }
    / HtmlVoidClosed

HtmlContent
    = Verbatim / Html / HtmlVoid

HtmlTagBegin
    = '<' !HtmlVoidTag tag:HtmlSymbol attributes:HtmlAttributes? '>' {
        return { tag, attributes }
    }
HtmlTagEnd
    = '</' tag:HtmlSymbol HtmlSpace '>' {
        return tag
    }
HtmlVoid
    = '<' tag:HtmlSymbol attributes:HtmlAttributes? ('/>' / '>') { return `<${tag}${attributes || ''}>` }
HtmlVoidClosed
    = '<' tag:HtmlSymbol attributes:HtmlAttributes? '/>' { return `<${tag}${attributes || ''}/>` }
HtmlVoidTag
    = 'br' / 'hr' / 'nop'

HtmlAttributes
    = HtmlSpace attributes:HtmlAttribute+ {
        return attributes.join('')
    }
HtmlAttribute
    = key:HtmlSymbol HtmlSpace
    value:('=' HtmlSpace value:$HtmlString HtmlSpace { return value })? {
        return typeof value === 'undefined' ? ` ${key}` : ` ${key}=${value}`
    }
HtmlSymbol
    = $[a-zA-Z0-9_-]+
HtmlSpace
    = [\r\n \t\u000C]*
HtmlString
    = '"' [^"]* '"' / '\'' [^']* '\'' / [^"'<> ]+
