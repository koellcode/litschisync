fs = require 'fs'
crypto = require 'crypto'
gm = require 'gm'
async = require 'async'
mkdirp = require 'mkdirp'
{abspath} = require('file').path
Promise = require 'bluebird'
{ExifImage} = require 'exif'

config = require './config'
Photo = require './model/photo'


bigFiles = "#{config.lychee_root}/uploads/big"
thumbFiles = "#{config.lychee_root}/uploads/thumb"

unlink = Promise.promisify fs.unlink

module.exports = (lychee) ->
    thumbnailQueue = null
    {HASH_NOT_EXIST_ERROR} = lychee.errors()

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

            lychee.insertPhoto photo
            copyReader = fs.createReadStream photo.meta.absolutePath
            @_transformThumb copyReader, photo, done
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

    _exifDateToISO8601: (exifDate) ->
        # hopefully this string is part of exif spec....
        # '2011:02:12 17:27:09' to ISO-8601
        [date, time] = exifDate.split ' '
        date = date.replace /:/g, '-'
        "#{date}T#{time}"

    _transformThumb: (reader, photo, done) ->
        absoluteThumbPath = photo.meta.absolutePathThumbTarget
        thumbWriter = fs.createWriteStream absoluteThumbPath
        new ExifImage image: photo.meta.absolutePath, (err, data) =>
            return unless data?
            {CreateDate} = data.exif
            iso8601 = @_exifDateToISO8601(CreateDate)
            photo.takestamp = new Date(iso8601).getTime() / 1000
            # TODO: add more exif when time come
            # update db meanwhile
            lychee.updatePhoto photo

        gm reader
        .resize '200', '200^'
        .gravity 'Center'
        .extent '200', '200'
        .size (err, size) ->
            photo.width = size.width
            photo.height = size.height
        .stream (err, stdout) ->
            stdout.pipe(thumbWriter)

        thumbWriter.once 'finish', ->
            console.log "#{absoluteThumbPath} generated"
            done()
        thumbWriter.once 'error', (err) -> console.log "writer error: ", err


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


