const { promises: fs } = require('fs')
const path = require('path')
const iconv = require('iconv-lite')
const jschardet = require('jschardet')
const PEG = require('pegjs')

async function listRecursive (root, relative = '') {
    const files = []
    const list = fs.readdir(path.join(root, relative), { withFileTypes: true })
    for (const entry of await list) {
        if (entry.isDirectory()) {
            const contents = await listRecursive(root, path.join(relative, entry.name))
            files.push(...contents)
        } else if (entry.isFile() && entry.name.endsWith('.txt')) {
            files.push(path.join(relative, entry.name))
        }
    }
    return files
}

async function readFile (file) {
    const buffer = await fs.readFile(file)
    const { encoding } = jschardet.detect(buffer)
    return iconv.decode(buffer, encoding || 'utf-8')
}

async function getTwikiParser () {
    const grammarPath = path.join(__dirname, 'grammar.pegjs')
    const grammar = await fs.readFile(grammarPath, 'utf-8')
    return PEG.generate(grammar)
}

const UNUSED_VARS = {}

function getTwikiParameters (list = '') {
    const parameters = {}
    for (const [, key, value] of list.matchAll(/([a-z]+)="([^"]*)"(?: |$)/g)) {
        parameters[key] = value
    }
    return parameters
}

function getTwikiVariable (variable, parameters, context) {
    parameters = getTwikiParameters(parameters)

    if (variable === 'ATTACHURL' || variable === 'ATTACHURLPATH') {
        return context.TOPIC
    } else if (variable === 'TOPIC') {
        return context.TOPIC
    } else if (variable === 'META:TOPICINFO') {
        const date = new Date(parameters.date * 1000)
        return `${parameters.author} - ${date.toDateString()} - Version ${parameters.version}<br>`
    } else if (variable === 'META:TOPICPARENT') {
        return `[[${parameters.name}][Parent topic: ${parameters.name}]]<br>`
    }

    UNUSED_VARS[variable] = (UNUSED_VARS[variable] || 0) + 1
    return ''
}

async function main (input) {
    const parser = await getTwikiParser()
    const files = await listRecursive(input)

    const links = files.map(filePath => path.join(
        path.dirname(filePath),
        path.basename(filePath, '.txt') + '.html'
    ))

    for (const filePath of files) {
        if (['TAPIR/ThirdProposal.txt'].includes(filePath) || filePath.startsWith('TWiki/') || filePath.startsWith('tmp/')) {
            console.error(filePath, 'skipped')
            continue
        }

        console.error(filePath)
        let file = await readFile(path.join(input, filePath))

        const outputDir = path.join('output', path.dirname(filePath))
        const outputPath = path.join(outputDir, path.basename(filePath, '.txt') + '.html')

        const context = {
            ATTACHURL: path.join(path.dirname(filePath), path.basename(filePath, '.txt')),
            TOPIC: path.basename(filePath, '.txt')
        }
        const options = {
            context,
            links: files
                .filter(siblingPath => path.dirname(filePath) === path.dirname(siblingPath))
                .map(siblingPath => path.basename(siblingPath, '.txt') + '.html')
                .concat(links)
        }

        file = file
            .replace(/%([A-Z:_]+)(?:\{(.+?)\})?%/g, (_, variable, parameters) => getTwikiVariable(variable, parameters, context))
            .replace(/http:\/\/wiki\.tdwg\.org\/twiki\/bin\/view\/SDD/g, '..')
            .replace(/(?!<\\)\\\n/g, '')

        try {
            const html = parser.parse(file, options)
            await fs.mkdir(outputDir, { recursive: true })
            fs.writeFile(outputPath, `<html>
            <head>
                <title>${context.TOPIC.split('.').reverse().join(' - ')} - TDWG</title>
                <meta charset="utf-8">
                <style>body { margin: 0 auto; max-width: 1000px; font-size: 16px; font-family: sans-serif; }</style>
            </head>
            <body>
                <nav>
                    <h1>
                        TDWG Wiki
                    </h1>
                </nav>
                ${html}
            </body>
            </html>`)
        } catch (error) {
            console.error(error.location)
            throw new Error(error.message)
        }
    }

    console.error(UNUSED_VARS)
}

main(...process.argv.slice(2)).catch(console.error)
