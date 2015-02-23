Promise = require 'bluebird'
mariastream = require 'mariastream'
just = require 'string-just'
tables =
    album: 'lychee_albums'
    photos: 'lychee_photos'

client = null

class HASH_NOT_EXIST_ERROR extends Error
    constructor: (message) ->
        super message

class ALBUM_CREATION_ERROR extends Error
    constructor: (message) ->
        super message

class ALBUM_NOT_EXIST_ERROR extends Error
    constructor: (message) ->
        super message

module.exports = ({host, db, user, password}) ->

    errors: ->
        HASH_NOT_EXIST_ERROR: HASH_NOT_EXIST_ERROR
        ALBUM_NOT_EXIST_ERROR: ALBUM_NOT_EXIST_ERROR

    connect: (cb = ->) ->
        client = mariastream()
        client.on 'error', (err) ->
            console.log err

        client.connect {host, db, user, password}, cb

    createAlbum: (title, publish = 0, sysstamp = new Date().getTime() / 1000) -> new Promise (resolve, reject) =>
        func = "insert into #{db}.#{tables.album}"
        columns = ['title', 'sysstamp', 'public', 'password']
        statement = "#{func} (#{@_getDef columns}) VALUES (#{@_getVal columns})"
        client.statement(statement).execute
            title: title
            sysstamp: sysstamp
            public: publish
        , (err, rows, info) ->
            return reject new ALBUM_CREATION_ERROR err.message if err
            resolve id: info.insertId

    addPhoto: (imageModel) -> new Promise (resolve, reject) =>
        imageModel = @_cloneAndStripModel imageModel
        func = "insert into #{db}.#{tables.photos}"
        columns = Object.keys(imageModel)
        statement = "#{func} (#{@_getDef columns}) VALUES (#{@_getVal columns})"
        client.statement(statement).execute imageModel, (err, rows, info) ->
            return reject err if err
            # TODO: more semantic error handling here plz
            resolve()

    updatePhoto: (imageModel) -> new Promise (resolve, reject) =>
        imageModel = @_cloneAndStripModel imageModel
        delete imageModel.id

        func = "update #{db}.#{tables.photos}"
        columns = Object.keys(imageModel)
        statement = "#{func} SET #{@_getUpdate columns} WHERE checksum = :checksum"
        client.statement(statement).execute imageModel, (err, rows, info) ->
            return reject err if err
            # TODO: more semantic error handling here plz
            resolve()

    removePhoto: (checksum) -> new Promise (resolve, reject) ->
        statement = "delete from #{db}.#{tables.photos} WHERE checksum = :checksum"
        client.statement(statement).execute {checksum}, (err, rows, info) ->
            return reject err if err
            resolve()

    albumExist: (title) -> new Promise (resolve, reject) ->
        client.statement "SELECT COUNT(title) as exist, id FROM #{db}.#{tables.album} WHERE title = :title"
        .readable title: title
        .on 'data', (data) ->
            if data.exist is '0'
                reject new ALBUM_NOT_EXIST_ERROR 'album not exist in db'
            else
                resolve data

    hashExist: (sha) -> new Promise (resolve, reject) ->
        client.statement "SELECT COUNT(checksum) as exist FROM #{db}.#{tables.photos} WHERE checksum = :checksum"
        .readable checksum: sha
        .on 'data', (data) ->
            if data.exist is '0'
                reject new HASH_NOT_EXIST_ERROR 'hash not exist in db'
            else
                resolve sha
        .on 'error', (err) ->
            reject err

    resetPhotos: -> new Promise (resolve, reject) ->
        statement = "delete from #{db}.#{tables.photos}"
        client.statement(statement).execute {}, (err, rows, info) ->
            return reject err if err
            console.log "removed #{info.affectedRows} photos"
            resolve()

    resetAlbums: -> new Promise (resolve, reject) ->
        statement = "delete from #{db}.#{tables.album}"
        client.statement(statement).execute {}, (err, rows, info) ->
            return reject err if err
            console.log "removed #{info.affectedRows} albums"
            resolve()

    insertPhoto: (imageModel) -> new Promise (resolve, reject) =>
        albumTitle = imageModel.meta.parentName
        imageModel.id = @_generatePhotoID()

        @albumExist albumTitle
        .bind this
        .catch ALBUM_NOT_EXIST_ERROR, ->
            @createAlbum albumTitle
        .then (albumInfo) ->
            imageModel.album = albumInfo.id
            @addPhoto imageModel
            console.log "#{imageModel.title} written in DB"
            resolve()
        .catch Error, (err) ->
            reject err

    reset: -> new Promise (resolve, reject) =>
        @resetPhotos()
        .then => @resetAlbums()
        .then -> resolve()

    _getDef: (columns) ->
        columns.join ', '

    _getVal: (columns) ->
        columns[0] = ":#{columns[0]}"
        columns.join ', :'

    _getUpdate: (columns) ->
        columns.map (column) -> "#{column} = :#{column}"
        .join ', '

    _cloneAndStripModel: (model) ->
        clone = JSON.parse JSON.stringify model
        delete clone.meta
        return clone

    _getRandomInt: (min, max) ->
        Math.floor(Math.random() * (max - min + 1)) + min

    _generatePhotoID: ->
        just.ljust "#{Date.now()}", 14, "#{@_getRandomInt 0, 9}"




