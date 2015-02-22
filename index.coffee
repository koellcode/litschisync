beholder = require 'beholder'
config = require './config'

lychee = require('./lychee-api')(config.lychee_database)
sync = require('./sync')(lychee)

watcher = beholder "#{config.lychee_sync_dir}/**/*"

watcher.on 'ready', ->
    console.log "litschisync is ready and watching #{config.lychee_sync_dir}"
    lychee.connect()
    sync.start watcher.list()

watcher.on 'new', (file, event) ->
    console.log '%s add detected.', file
    sync.addFile file

watcher.on 'remove', (file, event) ->
    console.log '%s removal detected.', file
    sync.removeFile file


