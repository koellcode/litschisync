async = require 'async'
Promise = require 'bluebird'
config = require './config'
fs = require 'fs'

module.exports = (lycheeDB, lycheeFile) ->
    thumbnailQueue = null

    start: (localFiles) ->
        localFiles = [localFiles] if not Array.isArray localFiles
        thumbnailQueue = async.queue @addEntry.bind(this), config.max_concurrent
        lycheeFile.initDirectory()
        .then ->
            thumbnailQueue.push file for file in localFiles

    addEntry: (file, done = ->) ->
        photo = lycheeFile.extractFileInfo file
        @_fileNotExist photo.meta.absolutePath
        .bind this
        .then ->
            @_setExifData photo
        .then ->
            copyReader = fs.createReadStream photo.meta.absolutePath
            lycheeFile.transformThumb(copyReader, photo)
            .then ->
                lycheeDB.insertPhoto photo
            .then ->
                done()
            lycheeFile.copyOriginal(copyReader, photo)

        .catch String, (err) ->
            done()

    removeEntry: (file, done = ->) ->
        photo = lycheeFile.extractFileInfo file
        lycheeDB.removePhoto photo.checksum
        .then ->
            lycheeFile.removeFile photo
            console.log "File: #{file} removed"
        .catch Error, (err) ->
            console.log "error on removal: ", err
            done err

    _fileNotExist: (file) -> new Promise (resolve, reject) =>
        # ask against database if sha1 is already synced
        lycheeDB.hashExist lycheeFile.getSHA1 file
            .then (hash) ->
                reject 'REASON' if hash
                resolve hash unless hash
            .catch Error, (err) -> reject err

    _setExifData: (photo) -> new Promise (resolve, reject) =>
        lycheeFile.getExif photo
        .then (data) =>
            return resolve() unless data?

            {CreateDate} = data.exif
            iso8601 = @_exifDateToISO8601(CreateDate)
            photo.takestamp = new Date(iso8601).getTime() / 1000
            resolve()

    _exifDateToISO8601: (exifDate) ->
        # hopefully this string is part of exif spec....
        # '2011:02:12 17:27:09' to ISO-8601
        [date, time] = exifDate.split ' '
        date = date.replace /:/g, '-'
        "#{date}T#{time}"


