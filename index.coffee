beholder = require 'beholder'
config = require './config'

lycheeDB = require('./lychee-api/db')(config.lychee_database)
lycheeFile = require './lychee-api/file'

sync = require('./sync')(lycheeDB, lycheeFile)

watcher = beholder "#{config.lychee_sync_dir}/*/*.+(jpg|JPG|jpeg)"
program = require 'commander'


program
    .usage('edit configure your coffee.conf')
    .option('-r, --reset', 'clean the whole lychee out from all photos and files')
    .parse(process.argv)

lycheeDB.connect ->

    if program.reset
        lycheeDB.reset().then -> process.exit 0


watcher.on 'ready', ->
    console.log "litschisync is ready and watching #{config.lychee_sync_dir}"
    sync.start watcher.list()

watcher.on 'new', (file, event) ->
    console.log '%s add detected.', file
    sync.addEntry file

watcher.on 'remove', (file, event) ->
    console.log '%s removal detected.', file
    sync.removeEntry file


