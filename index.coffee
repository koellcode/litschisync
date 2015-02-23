beholder = require 'beholder'
config = require './config'

lychee = require('./lychee-api')(config.lychee_database)
sync = require('./sync')(lychee)

watcher = beholder "#{config.lychee_sync_dir}/*/*.+(jpg|JPG|jpeg)"
program = require 'commander'


program
    .usage('edit configure your coffee.conf')
    .option('-r, --reset', 'clean the whole lychee out from all photos and files')
    .parse(process.argv)

lychee.connect ->

    if program.reset
        lychee.reset().then -> process.exit 0


watcher.on 'ready', ->
    console.log "litschisync is ready and watching #{config.lychee_sync_dir}"
    sync.start watcher.list()

watcher.on 'new', (file, event) ->
    console.log '%s add detected.', file
    sync.addFile file

watcher.on 'remove', (file, event) ->
    console.log '%s removal detected.', file
    sync.removeFile file


