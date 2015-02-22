fs = require 'fs'
crypto = require 'crypto'
gm = require 'graphicsmagick-stream'
async = require 'async'
just = require 'string-just'
mkdirp = require 'mkdirp'
{abspath} = require('file').path
Promise = require 'bluebird'

config = require './config'
Photo = require './model/photo'


bigFiles = "#{config.lychee_root}/uploads/big"
thumbFiles = "#{config.lychee_root}/uploads/thumb"

unlink = Promise.promisify fs.unlink

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
        @_fileExist photo.meta.absolutePath, (exists) =>
            return done() if exists

            copyReader = fs.createReadStream photo.meta.absolutePath
            copyReader.on 'end', => @_insertPhotoToDB photo, done

            @_transformThumb copyReader, photo
            @_copyOriginal copyReader, photo

    removeFile: (file, done = ->) ->
        photo = @_extractFileInfo abspath file
        lychee.removePhoto photo.checksum
        .then ->
            unlink photo.meta.absolutePathThumbTarget
        .then ->
            unlink photo.meta.absolutePathBigTarget
            done()
        .catch Error, (err) ->
            console.log "error on removal: ", err
            done err

    _fileExist: (filepath, cb) ->
        # ask against database if sha1 is already synced
        lychee.hashExist @_getSHA1 filepath
            .then -> cb true
            .catch HASH_NOT_EXIST_ERROR, (err) =>
                cb false

    _getSHA1: (filepath) ->
        shasum = crypto.createHash 'sha1'
        shasum.update filepath
        shasum.digest 'hex'

    _transformThumb: (reader, photo) ->
        absoluteThumbPath = photo.meta.absolutePathThumbTarget
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
        absoluteBigPath = photo.meta.absolutePathBigTarget
        outWriter = fs.createWriteStream absoluteBigPath
        outWriter.on 'finish', -> console.log "#{absoluteBigPath} copied"
        reader.pipe(outWriter)

    _extractFileInfo: (absolutePath) ->
        fotoModel = new Photo
        paths = absolutePath.split '/'
        fotoModel.title = paths.pop()
        fotoModel.description = new Date()
        fotoModel.id = just.ljust "#{Date.now()}", 14, '0'
        fotoModel.checksum = @_getSHA1 absolutePath

        fotoModel.meta = {}
        fotoModel.meta.parentName = paths.pop()
        fotoModel.meta.absolutePath = absolutePath
        fotoModel.meta.extension = absolutePath.split('.').pop()
        fotoModel.meta.absolutePathBigTarget = "#{bigFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"
        fotoModel.meta.absolutePathThumbTarget = "#{thumbFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        fotoModel.url = fotoModel.thumbUrl = "#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        return fotoModel

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



