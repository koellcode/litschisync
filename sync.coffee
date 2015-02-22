fs = require 'fs'
crypto = require 'crypto'
gm = require 'graphicsmagick-stream'
async = require 'async'
just = require 'string-just'
mkdirp = require 'mkdirp'
{abspath} = require('file').path

config = require './config'
Photo = require './model/photo'


bigFiles = "#{config.lychee_root}/uploads/big"
thumbFiles = "#{config.lychee_root}/uploads/thumb"


module.exports = (lychee) ->
    thumbnailQueue = null
    {HASH_NOT_EXIST_ERROR, ALBUM_NOT_EXIST_ERROR} = lychee.errors()

    start: (localFiles) ->
        localFiles = [localFiles] if not Array.isArray localFiles
        thumbnailQueue = async.queue @addFile.bind(this), 4

        async.each ["#{bigFiles}", "#{thumbFiles}"], (path, done) ->
            mkdirp path, null, done
        , (err) =>
            thumbnailQueue.push file for file in localFiles

    addFile: (file, done = ->) ->
        photo = @_extractFileInfo abspath file
        @_getSHA1FromFile photo.meta.absolutePath, (hash) =>
            return done() unless hash?

            photo.meta.hash = hash
            @_enrichFileInfo photo, hash
            copyReader = fs.createReadStream photo.meta.absolutePath
            copyReader.on 'end', => @_insertPhotoToDB photo, done

            @_transformThumb copyReader, photo
            @_copyOriginal copyReader, photo



    _getSHA1FromFile: (filepath, cb) ->
        shaStream = crypto.createHash 'sha1'
        shaStream.setEncoding 'hex'

        shaReader = fs.createReadStream filepath
        shaReader.on 'error', (err) -> console.log "shaReader error: ", err
        shaStream.on 'not_in_db', cb
        shaStream.on 'in_db', cb
        shaStream.on 'finish', @_handleSHA1
        shaReader.pipe(shaStream)


    _handleSHA1: ->
        shaHash = @read()
        # ask against database if sha1 is already synced
        lychee.hashExist(shaHash)
            .then => @emit 'in_db'
            .catch HASH_NOT_EXIST_ERROR, (err) =>
                @emit 'not_in_db', shaHash

    _transformThumb: (reader, photo) ->
        absoluteThumbPath = "#{thumbFiles}/#{photo.meta.hash}.#{photo.meta.extension}"
        thumbWriter = fs.createWriteStream absoluteThumbPath
        resize = gm
            format: 'jpg'
            scale:
                width: 500
                height: 500

        reader.pipe(resize()).pipe(thumbWriter)
        thumbWriter.on 'finish', -> console.log "#{absoluteThumbPath} generated"
        thumbWriter.on 'error', (err) -> console.log "writer error: ", err

    _copyOriginal: (reader, photo) ->
        absoluteBigPath = "#{bigFiles}/#{photo.meta.hash}.#{photo.meta.extension}"
        outWriter = fs.createWriteStream absoluteBigPath
        outWriter.on 'finish', -> console.log "#{absoluteBigPath} copied"
        reader.pipe(outWriter)

    _extractFileInfo: (absolutePath) ->
        fotoModel = new Photo
        paths = absolutePath.split '/'
        fotoModel.title = paths.pop()
        fotoModel.description = new Date()
        fotoModel.meta =
            parentName: paths.pop()
            absolutePath: absolutePath
            extension: absolutePath.split('.').pop()

        return fotoModel

    _enrichFileInfo: (fotoModel, hash) ->
        fotoModel.id = just.ljust "#{Date.now()}", 14, '0'
        fotoModel.url = fotoModel.thumbUrl = "#{fotoModel.meta.hash}.#{fotoModel.meta.extension}"
        fotoModel.checksum = "#{fotoModel.meta.hash}"

    _insertPhotoToDB: (photo, done = ->) ->
        albumTitle = photo.meta.parentName
        lychee.albumExist albumTitle
        .catch ALBUM_NOT_EXIST_ERROR, ->
            lychee.createAlbum albumTitle
        .then (albumInfo) ->
            photo.album = albumInfo.id
            lychee.insertPhoto photo
            console.log "#{photo.title} written in DB"
            done()
        .catch Error, (err) ->
            throw err



