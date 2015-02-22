fs = require 'fs'
crypto = require 'crypto'
gm = require 'gm'
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
            @_transformThumb copyReader, photo, =>
                @_insertPhotoToDB photo, done

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

    _transformThumb: (reader, photo, done) ->
        absoluteThumbPath = photo.meta.absolutePathThumbTarget
        thumbWriter = fs.createWriteStream absoluteThumbPath
        gm reader
        .resize 500, 500
        .stream (err, stdout) ->
            stdout.pipe(thumbWriter)

        thumbWriter.once 'finish', ->
            console.log "#{absoluteThumbPath} generated"
            done()
        thumbWriter.once 'error', (err) -> console.log "writer error: ", err

        gm reader
        .size (err, size) ->
            photo.width = size.width
            photo.height = size.height

    _copyOriginal: (reader, photo) ->
        absoluteBigPath = photo.meta.absolutePathBigTarget
        outWriter = fs.createWriteStream absoluteBigPath
        outWriter.once 'finish', -> console.log "#{absoluteBigPath} copied"
        reader.pipe(outWriter)

    _extractFileInfo: (absolutePath) ->
        fotoModel = new Photo
        paths = absolutePath.split '/'
        fotoModel.title = paths.pop()
        fotoModel.description = new Date()
        fotoModel.checksum = @_getSHA1 absolutePath

        fotoModel.meta = {}
        fotoModel.meta.parentName = paths.pop()
        fotoModel.meta.absolutePath = absolutePath
        fotoModel.meta.extension = absolutePath.split('.').pop()
        fotoModel.meta.absolutePathBigTarget = "#{bigFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"
        fotoModel.meta.absolutePathThumbTarget = "#{thumbFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        fotoModel.url = fotoModel.thumbUrl = "#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        return fotoModel

    _getRandomInt: (min, max) ->
        Math.floor(Math.random() * (max - min + 1)) + min

    _generatePhotoID: ->
        just.ljust "#{Date.now()}", 14, "#{@_getRandomInt 0, 9}"

    _insertPhotoToDB: (photo, done = ->) ->
        albumTitle = photo.meta.parentName
        photo.id = @_generatePhotoID()
        delete photo.meta

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



