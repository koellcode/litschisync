gm = require 'gm'
fs = require 'fs'
async = require 'async'
Promise = require 'bluebird'
unlink = Promise.promisify fs.unlink
{abspath} = require('file').path
mkdirp = require 'mkdirp'
crypto = require 'crypto'
{ExifImage} = require 'exif'

Photo = require '../model/photo'

config = require '../config'
bigFiles = "#{config.lychee_root}/uploads/big"
thumbFiles = "#{config.lychee_root}/uploads/thumb"


module.exports =
    getExif: (imageModel) -> new Promise (resolve, reject) =>
        new ExifImage image: imageModel.meta.absolutePath, (err, data) =>
            return resolve data

    initDirectory: -> new Promise (resolve, reject) ->
        async.each ["#{bigFiles}", "#{thumbFiles}"], (path, done) ->
            mkdirp path, null, done
        , (err) =>
            return reject err if err?
            resolve()

    removeFile: (photo) -> new Promise (resolve, reject) ->
        unlink photo.meta.absolutePathThumbTarget
        .then ->
            unlink photo.meta.absolutePathBigTarget
            resolve()

    transformThumb: (reader, photo) -> new Promise (resolve, reject) ->
        absoluteThumbPath = photo.meta.absolutePathThumbTarget
        thumbWriter = fs.createWriteStream absoluteThumbPath

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
            resolve()
        thumbWriter.once 'error', (err) ->
            console.log "writer error: ", err
            reject err

    copyOriginal: (reader, photo) ->
        absoluteBigPath = photo.meta.absolutePathBigTarget
        outWriter = fs.createWriteStream absoluteBigPath
        outWriter.once 'finish', -> console.log "#{absoluteBigPath} copied"
        reader.pipe(outWriter)

    extractFileInfo: (path) ->
        absolutePath = abspath path
        fotoModel = new Photo
        paths = absolutePath.split '/'
        fotoModel.title = paths.pop()
        fotoModel.description = new Date()
        fotoModel.checksum = @getSHA1 absolutePath

        fotoModel.meta = {}
        fotoModel.meta.parentName = paths.pop()
        fotoModel.meta.absolutePath = absolutePath
        fotoModel.meta.extension = absolutePath.split('.').pop()
        fotoModel.meta.absolutePathBigTarget = "#{bigFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"
        fotoModel.meta.absolutePathThumbTarget = "#{thumbFiles}/#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        fotoModel.url = fotoModel.thumbUrl = "#{fotoModel.checksum}.#{fotoModel.meta.extension}"

        return fotoModel

    getSHA1: (filepath) ->
        shasum = crypto.createHash 'sha1'
        shasum.update filepath
        shasum.digest 'hex'